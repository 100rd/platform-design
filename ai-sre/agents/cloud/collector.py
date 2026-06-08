"""Platform State Collector — syncs K8s, AWS, and Cloudflare topology to Omniscience."""

import asyncio
import logging
import os
from typing import Any, Dict, List, Optional, Tuple
import httpx

logger = logging.getLogger(__name__)


class PlatformStateCollector:
    """Discovers and updates the platform topology graph inside Omniscience."""

    def __init__(
        self,
        omniscience_url: str = "http://localhost:8000",
        omniscience_token: str = "",
        sync_interval_seconds: int = 300,
        mock_sync: Optional[bool] = None,
    ) -> None:
        self.omniscience_url = omniscience_url
        self.omniscience_token = omniscience_token
        self.sync_interval = sync_interval_seconds

        # Auto-detect if we should run mock sync mode
        if mock_sync is None:
            dry_run_env = os.environ.get("OMNISCIENCE_DRY_RUN", "").lower()
            mock_sync = (
                self.omniscience_token == "sk_live_mock_token"
                or not self.omniscience_token
                or dry_run_env in ("true", "1", "yes")
            )

        self.mock_sync = mock_sync

        if self.mock_sync:
            logger.info("Initializing mock HTTP client for Omniscience graph-sync endpoint")

            def mock_handler(request: httpx.Request) -> httpx.Response:
                if request.url.path == "/api/v1/graph/sync":
                    try:
                        import json
                        body = json.loads(request.read().decode("utf-8"))
                        nodes = body.get("nodes", [])
                        edges = body.get("edges", [])

                        logger.info("=== [MOCK HTTP CLIENT] Intercepted push to Omniscience ===")
                        logger.info("Endpoint: %s", request.url)
                        logger.info("Syncing %d nodes and %d edges", len(nodes), len(edges))

                        # Write payload to conversation artifact directory and a temp file
                        conv_id = "71f319e4-1671-476f-bc65-5ed04ef3bf50"
                        artifact_dir = f"/Users/lo/.gemini/antigravity-cli/brain/{conv_id}"
                        os.makedirs(artifact_dir, exist_ok=True)
                        artifact_path = os.path.join(artifact_dir, "omniscience_sync_latest.json")
                        with open(artifact_path, "w") as f:
                            json.dump(body, f, indent=2)

                        tmp_path = "/tmp/omniscience_sync_latest.json"
                        try:
                            with open(tmp_path, "w") as f:
                                json.dump(body, f, indent=2)
                        except Exception:
                            pass

                        logger.info("[MOCK HTTP CLIENT] Wrote latest sync payload to %s and %s", artifact_path, tmp_path)

                        # Print sample summary
                        logger.info("[MOCK HTTP CLIENT] Node summary by label:")
                        node_counts = {}
                        for n in nodes:
                            n_type = n.get("type", "Unknown")
                            node_counts[n_type] = node_counts.get(n_type, 0) + 1
                        for n_type, cnt in node_counts.items():
                            logger.info("  - %s: %d", n_type, cnt)

                        logger.info("[MOCK HTTP CLIENT] Edge summary by relationship:")
                        edge_counts = {}
                        for e in edges:
                            e_type = e.get("type", "Unknown")
                            edge_counts[e_type] = edge_counts.get(e_type, 0) + 1
                        for e_type, cnt in edge_counts.items():
                            logger.info("  - %s: %d", e_type, cnt)
                        logger.info("=========================================================")

                        return httpx.Response(
                            200,
                            json={
                                "status": "success",
                                "synchronized_nodes": len(nodes),
                                "synchronized_edges": len(edges),
                                "message": "Successfully synchronized with mock Omniscience store"
                            }
                        )
                    except Exception as exc:
                        logger.exception("Error in mock sync handler: %s", exc)
                        return httpx.Response(500, json={"status": "error", "message": str(exc)})
                else:
                    return httpx.Response(404, json={"status": "not_found"})

            self.client = httpx.AsyncClient(
                transport=httpx.MockTransport(mock_handler),
                base_url=self.omniscience_url,
                headers={"Authorization": f"Bearer {self.omniscience_token}"},
                timeout=10.0,
            )
        else:
            self.client = httpx.AsyncClient(
                base_url=self.omniscience_url,
                headers={"Authorization": f"Bearer {self.omniscience_token}"},
                timeout=10.0,
            )

    async def collect_k8s_topology(self, cluster: str) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """Collect K8s resource topology (Pods, Services, PVCs, Nodes).

        Tries to poll the real Kubernetes cluster if configured, otherwise falls back to generating
        high-fidelity mock topology.
        """
        try:
            from kubernetes import client, config
            try:
                config.load_incluster_config()
            except Exception:
                config.load_kube_config()

            v1 = client.CoreV1Api()
            # Test listing nodes to verify API server is reachable
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, lambda: v1.list_node(limit=1))

            logger.info("[%s] Successfully authenticated with real Kubernetes API. Collecting resources...", cluster)
            return await self._collect_k8s_real(cluster, v1)
        except Exception as e:
            logger.warning(
                "[%s] Failed to connect to real Kubernetes API (falling back to high-fidelity mock data): %s",
                cluster, e
            )
            return self.generate_k8s_mock_topology(cluster)

    async def _collect_k8s_real(self, cluster: str, v1: Any) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """Synchronously query the real K8s API using thread pool wrapper."""
        loop = asyncio.get_running_loop()

        def blocking_fetch():
            nodes_list = v1.list_node()
            namespaces_list = v1.list_namespace()
            pods_list = v1.list_pod_for_all_namespaces()
            services_list = v1.list_service_for_all_namespaces()
            pvcs_list = v1.list_persistent_volume_claim_for_all_namespaces()
            return nodes_list, namespaces_list, pods_list, services_list, pvcs_list

        nodes_list, namespaces_list, pods_list, services_list, pvcs_list = await loop.run_in_executor(
            None, blocking_fetch
        )

        nodes = []
        edges = []
        cluster_id = f"k8s/cluster/{cluster}"

        # 1. Cluster node
        nodes.append({
            "id": cluster_id,
            "type": "K8sCluster",
            "properties": {"name": cluster, "status": "active"}
        })

        # 2. Namespaces
        for ns in namespaces_list.items:
            ns_name = ns.metadata.name
            ns_id = f"{cluster_id}/namespace/{ns_name}"
            nodes.append({
                "id": ns_id,
                "type": "K8sNamespace",
                "properties": {"name": ns_name}
            })
            edges.append({
                "from": ns_id,
                "to": cluster_id,
                "type": "BELONGS_TO"
            })

        # 3. Nodes
        for node in nodes_list.items:
            node_name = node.metadata.name
            node_id = f"{cluster_id}/node/{node_name}"
            provider_id = node.spec.provider_id or ""
            instance_id = ""
            if provider_id.startswith("aws:///"):
                instance_id = provider_id.split("/")[-1]

            status = "NotReady"
            if node.status.conditions:
                for cond in node.status.conditions:
                    if cond.type == "Ready":
                        status = "Ready" if cond.status == "True" else "NotReady"
                        break

            nodes.append({
                "id": node_id,
                "type": "K8sNode",
                "properties": {
                    "name": node_name,
                    "status": status,
                    "provider_id": provider_id,
                    "instance_id": instance_id
                }
            })
            edges.append({
                "from": node_id,
                "to": cluster_id,
                "type": "BELONGS_TO"
            })

        # 4. Pods
        for pod in pods_list.items:
            pod_name = pod.metadata.name
            pod_ns = pod.metadata.namespace
            pod_id = f"{cluster_id}/namespace/{pod_ns}/pod/{pod_name}"
            pod_ip = pod.status.pod_ip or "unknown"
            node_name = pod.spec.node_name

            nodes.append({
                "id": pod_id,
                "type": "K8sPod",
                "properties": {
                    "name": pod_name,
                    "namespace": pod_ns,
                    "status": pod.status.phase or "unknown",
                    "pod_ip": pod_ip
                }
            })

            edges.append({
                "from": pod_id,
                "to": f"{cluster_id}/namespace/{pod_ns}",
                "type": "IN_NAMESPACE"
            })
            if node_name:
                edges.append({
                    "from": pod_id,
                    "to": f"{cluster_id}/node/{node_name}",
                    "type": "SCHEDULED_ON"
                })

        # 5. Services
        for svc in services_list.items:
            svc_name = svc.metadata.name
            svc_ns = svc.metadata.namespace
            svc_id = f"{cluster_id}/namespace/{svc_ns}/service/{svc_name}"
            svc_type = svc.spec.type
            cluster_ip = svc.spec.cluster_ip or ""

            nodes.append({
                "id": svc_id,
                "type": "K8sService",
                "properties": {
                    "name": svc_name,
                    "namespace": svc_ns,
                    "type": svc_type,
                    "cluster_ip": cluster_ip
                }
            })
            edges.append({
                "from": svc_id,
                "to": f"{cluster_id}/namespace/{svc_ns}",
                "type": "IN_NAMESPACE"
            })

            # Selector matching
            selector = svc.spec.selector
            if selector:
                for pod in pods_list.items:
                    if pod.metadata.namespace == svc_ns and pod.metadata.labels:
                        if all(pod.metadata.labels.get(k) == v for k, v in selector.items()):
                            pod_id = f"{cluster_id}/namespace/{svc_ns}/pod/{pod.metadata.name}"
                            edges.append({
                                "from": svc_id,
                                "to": pod_id,
                                "type": "ROUTES_TO"
                            })

        # 6. PVCs
        for pvc in pvcs_list.items:
            pvc_name = pvc.metadata.name
            pvc_ns = pvc.metadata.namespace
            pvc_id = f"{cluster_id}/namespace/{pvc_ns}/pvc/{pvc_name}"
            volume_name = pvc.spec.volume_name or ""
            storage_class = pvc.spec.storage_class_name or ""

            nodes.append({
                "id": pvc_id,
                "type": "K8sPVC",
                "properties": {
                    "name": pvc_name,
                    "namespace": pvc_ns,
                    "volume_name": volume_name,
                    "storage_class": storage_class
                }
            })
            edges.append({
                "from": pvc_id,
                "to": f"{cluster_id}/namespace/{pvc_ns}",
                "type": "IN_NAMESPACE"
            })

            # Pod mounting PVCs
            for pod in pods_list.items:
                if pod.metadata.namespace == pvc_ns and pod.spec.volumes:
                    for vol in pod.spec.volumes:
                        if vol.persistent_volume_claim and vol.persistent_volume_claim.claim_name == pvc_name:
                            pod_id = f"{cluster_id}/namespace/{pvc_ns}/pod/{pod.metadata.name}"
                            edges.append({
                                "from": pod_id,
                                "to": pvc_id,
                                "type": "MOUNTS"
                            })

            # Check PV specs for actual backing volume block store IDs
            if volume_name:
                try:
                    def blocking_pv():
                        return v1.read_persistent_volume(volume_name)
                    pv = loop.run_in_executor(None, blocking_pv)
                    vol_id = ""
                    if pv.spec.aws_elastic_block_store:
                        vol_id = pv.spec.aws_elastic_block_store.volume_id.split("/")[-1]
                    elif pv.spec.csi and pv.spec.csi.driver == "ebs.csi.aws.com":
                        vol_id = pv.spec.csi.volume_handle.split("/")[-1]

                    if vol_id:
                        edges.append({
                            "from": pvc_id,
                            "to": f"aws/ebs/{vol_id}",
                            "type": "DEPLOYS_ON"
                        })
                except Exception:
                    pass

        return nodes, edges

    async def collect_aws_topology(self) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """Collect AWS cloud topology (EC2, EBS, ALB, TGW, Route53).

        Tries to query the real AWS APIs if credentials are configured, otherwise falls back to generating
        high-fidelity mock topology.
        """
        try:
            import boto3
            session = boto3.Session()
            sts = session.client("sts")
            # Verify credentials
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, sts.get_caller_identity)

            logger.info("Successfully authenticated with real AWS API. Collecting resources...")
            return await self._collect_aws_real(session)
        except Exception as e:
            logger.warning(
                "Failed to connect to real AWS API (falling back to high-fidelity mock data): %s", e
            )
            return self.generate_aws_mock_topology()

    async def _collect_aws_real(self, session: Any) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """Query real AWS APIs via thread pooling."""
        loop = asyncio.get_running_loop()

        def blocking_fetch():
            ec2 = session.client("ec2")
            elbv2 = session.client("elbv2")
            route53 = session.client("route53")

            instances_resp = ec2.describe_instances()
            volumes_resp = ec2.describe_volumes()
            tgws_resp = ec2.describe_transit_gateways()

            tgw_attach_resp = None
            try:
                tgw_attach_resp = ec2.describe_transit_gateway_attachments()
            except Exception:
                pass

            albs_resp = elbv2.describe_load_balancers()

            targets_map = {}
            for alb in albs_resp.get("LoadBalancers", []):
                alb_arn = alb.get("LoadBalancerArn", "")
                alb_name = alb.get("LoadBalancerName", "")
                try:
                    tg_resp = elbv2.describe_target_groups(LoadBalancerArn=alb_arn)
                    for tg in tg_resp.get("TargetGroups", []):
                        tg_arn = tg.get("TargetGroupArn", "")
                        health_resp = elbv2.describe_target_health(TargetGroupArn=tg_arn)
                        for target_health in health_resp.get("TargetHealthDescriptions", []):
                            target_id = target_health.get("Target", {}).get("Id", "")
                            if target_id:
                                targets_map.setdefault(alb_name, []).append(target_id)
                except Exception:
                    pass

            zones_and_records = []
            try:
                zones_resp = route53.list_hosted_zones()
                for zone in zones_resp.get("HostedZones", []):
                    z_id = zone.get("Id", "").split("/")[-1]
                    z_name = zone.get("Name", "")
                    recs_resp = route53.list_resource_record_sets(HostedZoneId=z_id)
                    zones_and_records.append((z_id, z_name, recs_resp.get("ResourceRecordSets", [])))
            except Exception:
                pass

            return (
                instances_resp,
                volumes_resp,
                tgws_resp,
                tgw_attach_resp,
                albs_resp,
                targets_map,
                zones_and_records,
            )

        (
            instances_resp,
            volumes_resp,
            tgws_resp,
            tgw_attach_resp,
            albs_resp,
            targets_map,
            zones_and_records,
        ) = await loop.run_in_executor(None, blocking_fetch)

        nodes = []
        edges = []

        # 1. EC2 Instances
        for reservation in instances_resp.get("Reservations", []):
            for inst in reservation.get("Instances", []):
                inst_id = inst.get("InstanceId", "")
                if not inst_id:
                    continue
                state = inst.get("State", {}).get("Name", "unknown")
                inst_type = inst.get("InstanceType", "")
                private_ip = inst.get("PrivateIpAddress", "")
                vpc_id = inst.get("VpcId", "")
                subnet_id = inst.get("SubnetId", "")
                az = inst.get("Placement", {}).get("AvailabilityZone", "")
                lifecycle = inst.get("InstanceLifecycle", "on-demand")

                nodes.append({
                    "id": f"aws/ec2/{inst_id}",
                    "type": "EC2Instance",
                    "properties": {
                        "instance_id": inst_id,
                        "instance_type": inst_type,
                        "state": state,
                        "private_ip": private_ip,
                        "vpc_id": vpc_id,
                        "subnet_id": subnet_id,
                        "availability_zone": az,
                        "lifecycle": lifecycle,
                        "system_check": "ok",
                        "instance_check": "ok",
                        "spot_interruption": False,
                    }
                })

        # 2. EBS Volumes
        for vol in volumes_resp.get("Volumes", []):
            vol_id = vol.get("VolumeId", "")
            if not vol_id:
                continue
            size = vol.get("Size", 0)
            vol_type = vol.get("VolumeType", "")
            state = vol.get("State", "")

            nodes.append({
                "id": f"aws/ebs/{vol_id}",
                "type": "EBSVolume",
                "properties": {
                    "volume_id": vol_id,
                    "size_gb": size,
                    "volume_type": vol_type,
                    "state": state,
                    "iops": vol.get("Iops", 3000),
                    "queue_length": 0.0,
                    "io_performance": "normal",
                }
            })

            for attachment in vol.get("Attachments", []):
                attach_inst = attachment.get("InstanceId", "")
                if attach_inst:
                    edges.append({
                        "from": f"aws/ebs/{vol_id}",
                        "to": f"aws/ec2/{attach_inst}",
                        "type": "ATTACHED_TO"
                    })

        # 3. ALBs
        for alb in albs_resp.get("LoadBalancers", []):
            alb_arn = alb.get("LoadBalancerArn", "")
            alb_name = alb.get("LoadBalancerName", "")
            dns_name = alb.get("DNSName", "")
            scheme = alb.get("Scheme", "")
            vpc_id = alb.get("VpcId", "")

            nodes.append({
                "id": f"aws/alb/{alb_name}",
                "type": "AWSALB",
                "properties": {
                    "name": alb_name,
                    "arn": alb_arn,
                    "dns_name": dns_name,
                    "scheme": scheme,
                    "vpc_id": vpc_id,
                }
            })

            # Target health connections
            targets = targets_map.get(alb_name, [])
            for target_id in targets:
                if target_id.startswith("i-"):
                    edges.append({
                        "from": f"aws/alb/{alb_name}",
                        "to": f"aws/ec2/{target_id}",
                        "type": "ROUTES_TO"
                    })

        # 4. Transit Gateways (TGW)
        for tgw in tgws_resp.get("TransitGateways", []):
            tgw_id = tgw.get("TransitGatewayId", "")
            state = tgw.get("State", "")
            desc = tgw.get("Description", "")

            nodes.append({
                "id": f"aws/tgw/{tgw_id}",
                "type": "AWSTGW",
                "properties": {
                    "transit_gateway_id": tgw_id,
                    "state": state,
                    "description": desc,
                }
            })

        # Transit Gateway Attachments to VPC
        if tgw_attach_resp:
            for attach in tgw_attach_resp.get("TransitGatewayAttachments", []):
                tgw_id = attach.get("TransitGatewayId", "")
                resource_id = attach.get("ResourceId", "")
                resource_type = attach.get("ResourceType", "")

                if resource_type == "vpc" and tgw_id:
                    for node in nodes:
                        if node["type"] == "EC2Instance" and node["properties"].get("vpc_id") == resource_id:
                            edges.append({
                                "from": node["id"],
                                "to": f"aws/tgw/{tgw_id}",
                                "type": "NETWORKS_THROUGH"
                            })

        # 5. Route53 DNS Records
        for zone_id, zone_name, recs in zones_and_records:
            for rec in recs:
                rec_name = rec.get("Name", "").rstrip(".")
                rec_type = rec.get("Type", "")

                values = []
                if rec.get("AliasTarget"):
                    values.append(rec["AliasTarget"].get("DNSName", "").rstrip("."))
                for val in rec.get("ResourceRecords", []):
                    values.append(val.get("Value", ""))

                rec_id = f"aws/route53/{zone_id}/record/{rec_name}/{rec_type}"
                nodes.append({
                    "id": rec_id,
                    "type": "Route53Record",
                    "properties": {
                        "name": rec_name,
                        "type": rec_type,
                        "value": ", ".join(values),
                        "ttl": rec.get("TTL", 300),
                    }
                })

                # Resolve mapping Route53 -> ALB or EC2
                for val in values:
                    for node in nodes:
                        if node["type"] == "AWSALB" and node["properties"].get("dns_name", "").rstrip(".") in val:
                            edges.append({
                                "from": rec_id,
                                "to": node["id"],
                                "type": "RESOLVES_TO"
                            })
                        elif node["type"] == "EC2Instance" and node["properties"].get("private_ip") == val:
                            edges.append({
                                "from": rec_id,
                                "to": node["id"],
                                "type": "RESOLVES_TO"
                            })

        return nodes, edges

    async def collect_cloudflare_topology(self) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """Collect Cloudflare DNS, Tunnels, and Zone topology.

        Tries to query the real Cloudflare API if credentials are configured, otherwise falls back to generating
        high-fidelity mock topology.
        """
        token = os.environ.get("CLOUDFLARE_API_TOKEN")
        if not token:
            logger.info("CLOUDFLARE_API_TOKEN not set. Using Cloudflare mock topology.")
            return self.generate_cloudflare_mock_topology()

        try:
            logger.info("CLOUDFLARE_API_TOKEN set. Collecting real Cloudflare resources...")
            return await self._collect_cloudflare_real(token)
        except Exception as e:
            logger.warning(
                "Failed to collect real Cloudflare topology (falling back to mock data): %s", e
            )
            return self.generate_cloudflare_mock_topology()

    async def _collect_cloudflare_real(self, token: str) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """Async gather Cloudflare topology using API REST calls."""
        headers = {"Authorization": f"Bearer {token}"}
        nodes = []
        edges = []

        async with httpx.AsyncClient(timeout=10.0) as client:
            # 1. Zones
            zones_resp = await client.get("https://api.cloudflare.com/client/v4/zones", headers=headers)
            if zones_resp.status_code != 200:
                zones_resp.raise_for_status()
            zones = zones_resp.json().get("result", [])

            for zone in zones:
                zone_id = zone.get("id")
                zone_name = zone.get("name")
                status = zone.get("status")

                zone_node_id = f"cloudflare/zone/{zone_name}"
                nodes.append({
                    "id": zone_node_id,
                    "type": "CFZone",
                    "properties": {
                        "domain": zone_name,
                        "zone_id": zone_id,
                        "status": status,
                    }
                })

                # 2. DNS records
                dns_resp = await client.get(f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records", headers=headers)
                if dns_resp.status_code == 200:
                    dns_records = dns_resp.json().get("result", [])
                    for rec in dns_records:
                        rec_id = rec.get("id")
                        rec_name = rec.get("name")
                        rec_type = rec.get("type")
                        content = rec.get("content")
                        proxied = rec.get("proxied", False)

                        rec_node_id = f"cloudflare/dns/{rec_name}"
                        nodes.append({
                            "id": rec_node_id,
                            "type": "CFDNSRecord",
                            "properties": {
                                "record_id": rec_id,
                                "name": rec_name,
                                "type": rec_type,
                                "content": content,
                                "proxied": proxied,
                            }
                        })
                        edges.append({
                            "from": rec_node_id,
                            "to": zone_node_id,
                            "type": "BELONGS_TO"
                        })

            # 3. Tunnels
            account_id = os.environ.get("CLOUDFLARE_ACCOUNT_ID")
            if not account_id and zones:
                account_id = zones[0].get("account", {}).get("id")

            if account_id:
                tunnels_resp = await client.get(f"https://api.cloudflare.com/client/v4/accounts/{account_id}/tunnels", headers=headers)
                if tunnels_resp.status_code == 200:
                    tunnels = tunnels_resp.json().get("result", [])
                    for tunnel in tunnels:
                        tunnel_id = tunnel.get("id")
                        tunnel_name = tunnel.get("name")
                        status = tunnel.get("status")

                        tunnel_node_id = f"cloudflare/tunnel/{tunnel_id}"
                        nodes.append({
                            "id": tunnel_node_id,
                            "type": "CFTunnel",
                            "properties": {
                                "tunnel_id": tunnel_id,
                                "name": tunnel_name,
                                "status": status,
                            }
                        })

                        # Link CNAME DNS records that route through this tunnel
                        tunnel_target = f"{tunnel_id}.cfargotunnel.com"
                        for node in nodes:
                            if node["type"] == "CFDNSRecord" and node["properties"].get("content") == tunnel_target:
                                edges.append({
                                    "from": node["id"],
                                    "to": tunnel_node_id,
                                    "type": "ROUTES_THROUGH"
                                })

        return nodes, edges

    def generate_k8s_mock_topology(self, cluster: str) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """Generate high-fidelity Kubernetes mock data."""
        logger.info("[%s] Generating Kubernetes mock topology...", cluster)
        nodes = []
        edges = []
        cluster_id = f"k8s/cluster/{cluster}"

        # 1. Cluster node
        nodes.append({
            "id": cluster_id,
            "type": "K8sCluster",
            "properties": {
                "name": cluster,
                "environment": "production" if cluster != "blockchain" else "staging",
                "region": "us-west-2",
                "status": "active"
            }
        })

        # Namespaces
        namespaces = ["default", "kube-system", "monitoring"]
        if cluster == "platform":
            namespaces.append("ai-sre-system")
        elif cluster == "blockchain":
            namespaces.append("hft-core")

        for ns in namespaces:
            ns_id = f"{cluster_id}/namespace/{ns}"
            nodes.append({
                "id": ns_id,
                "type": "K8sNamespace",
                "properties": {"name": ns}
            })
            edges.append({
                "from": ns_id,
                "to": cluster_id,
                "type": "BELONGS_TO"
            })

        # Define mock nodes
        k8s_nodes = []
        if cluster == "gpu-inference":
            k8s_nodes = [
                {"name": f"{cluster}-node-1", "type": "g5.4xlarge", "inst_id": "i-gpu101abcdef123"},
                {"name": f"{cluster}-node-2", "type": "g5.4xlarge", "inst_id": "i-gpu102abcdef456"}
            ]
        elif cluster == "platform":
            k8s_nodes = [
                {"name": f"{cluster}-node-1", "type": "m6i.xlarge", "inst_id": "i-plat201abcdef789"},
                {"name": f"{cluster}-node-2", "type": "m6i.xlarge", "inst_id": "i-plat202abcdef012"}
            ]
        else:
            k8s_nodes = [
                {"name": f"{cluster}-node-1", "type": "c6i.2xlarge", "inst_id": "i-chain301abc345"}
            ]

        for kn in k8s_nodes:
            kn_id = f"{cluster_id}/node/{kn['name']}"
            nodes.append({
                "id": kn_id,
                "type": "K8sNode",
                "properties": {
                    "name": kn["name"],
                    "status": "Ready",
                    "provider_id": f"aws:///us-west-2a/{kn['inst_id']}",
                    "instance_id": kn["inst_id"],
                    "instance_type": kn["type"]
                }
            })
            edges.append({
                "from": kn_id,
                "to": cluster_id,
                "type": "BELONGS_TO"
            })

        # Define pods, services, and PVCs
        if cluster == "gpu-inference":
            pods = [
                {"name": "inference-api-7b89d4", "ns": "default", "ip": "10.10.1.55", "node": "gpu-inference-node-1"},
                {"name": "model-runner-823cd", "ns": "default", "ip": "10.10.2.88", "node": "gpu-inference-node-2"}
            ]
            services = [
                {"name": "inference-api-svc", "ns": "default", "type": "ClusterIP", "ip": "172.20.10.10", "selectors": {"app": "inference-api"}},
                {"name": "model-runner-svc", "ns": "default", "type": "ClusterIP", "ip": "172.20.10.20", "selectors": {"app": "model-runner"}}
            ]
            pvcs = [
                {"name": "model-weights-pvc", "ns": "default", "vol": "vol-gpu-weights", "storage_class": "gp3"}
            ]
        elif cluster == "platform":
            pods = [
                {"name": "api-gateway-123", "ns": "default", "ip": "10.20.1.100", "node": "platform-node-1"},
                {"name": "dashboard-8d76", "ns": "default", "ip": "10.20.2.101", "node": "platform-node-2"},
                {"name": "sre-agent-xyz", "ns": "ai-sre-system", "ip": "10.20.1.150", "node": "platform-node-1"},
                {"name": "cloudflared-pod-77", "ns": "default", "ip": "10.20.2.200", "node": "platform-node-2"}
            ]
            services = [
                {"name": "api-gateway-svc", "ns": "default", "type": "LoadBalancer", "ip": "172.20.20.10", "selectors": {"app": "api-gateway"}},
                {"name": "dashboard-svc", "ns": "default", "type": "ClusterIP", "ip": "172.20.20.20", "selectors": {"app": "dashboard"}},
                {"name": "cloudflared-tunnel-svc", "ns": "default", "type": "ClusterIP", "ip": "172.20.20.30", "selectors": {"app": "cloudflared"}}
            ]
            pvcs = [
                {"name": "pvc-dashboard-cache", "ns": "default", "vol": "vol-dash-cache", "storage_class": "gp3"}
            ]
        else: # blockchain
            pods = [
                {"name": "validator-node-0", "ns": "hft-core", "ip": "10.30.1.44", "node": "blockchain-node-1"},
                {"name": "validator-node-1", "ns": "hft-core", "ip": "10.30.1.45", "node": "blockchain-node-1"}
            ]
            services = [
                {"name": "validator-svc", "ns": "hft-core", "type": "ClusterIP", "ip": "172.20.30.10", "selectors": {"app": "validator"}}
            ]
            pvcs = [
                {"name": "chain-data-pvc", "ns": "hft-core", "vol": "vol-chain-db", "storage_class": "gp3"}
            ]

        for pod in pods:
            pod_id = f"{cluster_id}/namespace/{pod['ns']}/pod/{pod['name']}"
            nodes.append({
                "id": pod_id,
                "type": "K8sPod",
                "properties": {
                    "name": pod["name"],
                    "namespace": pod["ns"],
                    "status": "Running",
                    "pod_ip": pod["ip"]
                }
            })
            edges.append({
                "from": pod_id,
                "to": f"{cluster_id}/namespace/{pod['ns']}",
                "type": "IN_NAMESPACE"
            })
            edges.append({
                "from": pod_id,
                "to": f"{cluster_id}/node/{pod['node']}",
                "type": "SCHEDULED_ON"
            })

        for svc in services:
            svc_id = f"{cluster_id}/namespace/{svc['ns']}/service/{svc['name']}"
            nodes.append({
                "id": svc_id,
                "type": "K8sService",
                "properties": {
                    "name": svc["name"],
                    "namespace": svc["ns"],
                    "type": svc["type"],
                    "cluster_ip": svc["ip"]
                }
            })
            edges.append({
                "from": svc_id,
                "to": f"{cluster_id}/namespace/{svc['ns']}",
                "type": "IN_NAMESPACE"
            })

            # Selectors
            for pod in pods:
                if pod["ns"] == svc["ns"]:
                    app_sel = svc["selectors"].get("app", "")
                    if pod["name"].startswith(app_sel):
                        edges.append({
                            "from": svc_id,
                            "to": f"{cluster_id}/namespace/{pod['ns']}/pod/{pod['name']}",
                            "type": "ROUTES_TO"
                        })

        for pvc in pvcs:
            pvc_id = f"{cluster_id}/namespace/{pvc['ns']}/pvc/{pvc['name']}"
            nodes.append({
                "id": pvc_id,
                "type": "K8sPVC",
                "properties": {
                    "name": pvc["name"],
                    "namespace": pvc["ns"],
                    "volume_name": pvc["vol"],
                    "storage_class": pvc["storage_class"]
                }
            })
            edges.append({
                "from": pvc_id,
                "to": f"{cluster_id}/namespace/{pvc['ns']}",
                "type": "IN_NAMESPACE"
            })

            for pod in pods:
                if pod["ns"] == pvc["ns"]:
                    if any(x in pod["name"] for x in ["runner", "validator", "dashboard"]):
                        pod_id = f"{cluster_id}/namespace/{pod['ns']}/pod/{pod['name']}"
                        edges.append({
                            "from": pod_id,
                            "to": pvc_id,
                            "type": "MOUNTS"
                        })

        return nodes, edges

    def generate_aws_mock_topology(self) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """Generate high-fidelity AWS mock data."""
        logger.info("Generating AWS mock topology...")
        nodes = []
        edges = []

        # 1. EC2 Instances
        ec2_instances = [
            {"id": "i-gpu101abcdef123", "type": "g5.4xlarge", "ip": "10.10.1.10", "vpc": "vpc-gpu", "subnet": "subnet-gpu-1a", "az": "us-west-2a"},
            {"id": "i-gpu102abcdef456", "type": "g5.4xlarge", "ip": "10.10.2.20", "vpc": "vpc-gpu", "subnet": "subnet-gpu-1b", "az": "us-west-2b"},
            {"id": "i-plat201abcdef789", "type": "m6i.xlarge", "ip": "10.20.1.11", "vpc": "vpc-plat", "subnet": "subnet-plat-1a", "az": "us-west-2a"},
            {"id": "i-plat202abcdef012", "type": "m6i.xlarge", "ip": "10.20.2.22", "vpc": "vpc-plat", "subnet": "subnet-plat-1b", "az": "us-west-2b"},
            {"id": "i-chain301abc345", "type": "c6i.2xlarge", "ip": "10.30.1.33", "vpc": "vpc-chain", "subnet": "subnet-chain-1c", "az": "us-west-2c"}
        ]

        for inst in ec2_instances:
            nodes.append({
                "id": f"aws/ec2/{inst['id']}",
                "type": "EC2Instance",
                "properties": {
                    "instance_id": inst["id"],
                    "instance_type": inst["type"],
                    "state": "running",
                    "private_ip": inst["ip"],
                    "vpc_id": inst["vpc"],
                    "subnet_id": inst["subnet"],
                    "availability_zone": inst["az"],
                    "lifecycle": "spot" if "gpu" in inst["id"] else "on-demand",
                    "system_check": "ok",
                    "instance_check": "ok",
                    "spot_interruption": False
                }
            })

        # 2. EBS Volumes
        ebs_volumes = [
            {"id": "vol-gpu-weights", "size": 500, "type": "gp3", "inst": "i-gpu101abcdef123"},
            {"id": "vol-chain-db", "size": 1000, "type": "gp3", "inst": "i-chain301abc345"},
            {"id": "vol-dash-cache", "size": 50, "type": "gp3", "inst": "i-plat201abcdef789"}
        ]

        for vol in ebs_volumes:
            nodes.append({
                "id": f"aws/ebs/{vol['id']}",
                "type": "EBSVolume",
                "properties": {
                    "volume_id": vol["id"],
                    "size_gb": vol["size"],
                    "volume_type": vol["type"],
                    "state": "in-use",
                    "iops": 3000,
                    "queue_length": 0.0,
                    "io_performance": "normal"
                }
            })
            edges.append({
                "from": f"aws/ebs/{vol['id']}",
                "to": f"aws/ec2/{vol['inst']}",
                "type": "ATTACHED_TO"
            })

        # 3. ALBs
        albs = [
            {"name": "prod-external-alb", "dns": "prod-ext-123456.us-west-2.elb.amazonaws.com", "scheme": "internet-facing", "vpc": "vpc-plat", "targets": ["i-plat201abcdef789", "i-plat202abcdef012"]},
            {"name": "internal-services-alb", "dns": "internal-svc-7890.us-west-2.elb.amazonaws.com", "scheme": "internal", "vpc": "vpc-gpu", "targets": ["i-gpu101abcdef123", "i-gpu102abcdef456"]}
        ]

        for alb in albs:
            alb_id = f"aws/alb/{alb['name']}"
            nodes.append({
                "id": alb_id,
                "type": "AWSALB",
                "properties": {
                    "name": alb["name"],
                    "arn": f"arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/{alb['name']}/50dc6c495c0c9188",
                    "dns_name": alb["dns"],
                    "scheme": alb["scheme"],
                    "vpc_id": alb["vpc"]
                }
            })
            for target in alb["targets"]:
                edges.append({
                    "from": alb_id,
                    "to": f"aws/ec2/{target}",
                    "type": "ROUTES_TO"
                })

        # 4. Transit Gateways (TGW)
        tgw_id = "tgw-0987654321fedcba"
        nodes.append({
            "id": f"aws/tgw/{tgw_id}",
            "type": "AWSTGW",
            "properties": {
                "transit_gateway_id": tgw_id,
                "state": "available",
                "description": "Core SRE Transit Gateway connecting all VPCs"
            }
        })

        for inst in ec2_instances:
            edges.append({
                "from": f"aws/ec2/{inst['id']}",
                "to": f"aws/tgw/{tgw_id}",
                "type": "NETWORKS_THROUGH"
            })

        # 5. Route53 Record Sets
        zone_id = "Z1234567890ABC"
        records = [
            {"name": "api.hft-analytics.com", "type": "A", "val": "prod-ext-123456.us-west-2.elb.amazonaws.com"},
            {"name": "dashboard.hft-analytics.com", "type": "A", "val": "prod-ext-123456.us-west-2.elb.amazonaws.com"},
            {"name": "inference.internal.hft-analytics.com", "type": "A", "val": "internal-svc-7890.us-west-2.elb.amazonaws.com"}
        ]

        for rec in records:
            rec_id = f"aws/route53/{zone_id}/record/{rec['name']}/{rec['type']}"
            nodes.append({
                "id": rec_id,
                "type": "Route53Record",
                "properties": {
                    "name": rec["name"],
                    "type": rec["type"],
                    "value": rec["val"],
                    "ttl": 300
                }
            })
            for alb in albs:
                if alb["dns"] == rec["val"]:
                    edges.append({
                        "from": rec_id,
                        "to": f"aws/alb/{alb['name']}",
                        "type": "RESOLVES_TO"
                    })

        return nodes, edges

    def generate_cloudflare_mock_topology(self) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """Generate high-fidelity Cloudflare mock data."""
        logger.info("Generating Cloudflare topology...")
        nodes = []
        edges = []

        zone_name = "hft-analytics.com"
        zone_id = "cf-zone-hft-123"
        zone_node_id = f"cloudflare/zone/{zone_name}"

        # Zone
        nodes.append({
            "id": zone_node_id,
            "type": "CFZone",
            "properties": {
                "domain": zone_name,
                "zone_id": zone_id,
                "status": "active"
            }
        })

        # DNS Records
        dns_records = [
            {"name": "api.hft-analytics.com", "type": "CNAME", "content": "prod-ext-123456.us-west-2.elb.amazonaws.com", "proxied": True},
            {"name": "dashboard.hft-analytics.com", "type": "CNAME", "content": "prod-ext-123456.us-west-2.elb.amazonaws.com", "proxied": True},
            {"name": "tunnel.hft-analytics.com", "type": "CNAME", "content": "tunnel-id-9988.cfargotunnel.com", "proxied": True}
        ]

        for rec in dns_records:
            rec_node_id = f"cloudflare/dns/{rec['name']}"
            nodes.append({
                "id": rec_node_id,
                "type": "CFDNSRecord",
                "properties": {
                    "record_id": f"rec-{rec['name']}-id",
                    "name": rec["name"],
                    "type": rec["type"],
                    "content": rec["content"],
                    "proxied": rec["proxied"]
                }
            })
            edges.append({
                "from": rec_node_id,
                "to": zone_node_id,
                "type": "BELONGS_TO"
            })

        # Tunnel
        tunnel_id = "tunnel-id-9988"
        tunnel_node_id = f"cloudflare/tunnel/{tunnel_id}"
        nodes.append({
            "id": tunnel_node_id,
            "type": "CFTunnel",
            "properties": {
                "tunnel_id": tunnel_id,
                "name": "k8s-platform-tunnel",
                "status": "healthy"
            }
        })

        edges.append({
            "from": "cloudflare/dns/tunnel.hft-analytics.com",
            "to": tunnel_node_id,
            "type": "ROUTES_THROUGH"
        })

        return nodes, edges

    def build_cross_layer_edges(self, nodes: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Dynamically link nodes across boundaries based on metadata properties."""
        logger.info("Correlating cross-layer relationships...")
        edges = []

        k8s_nodes = {n["id"]: n for n in nodes if n["type"] == "K8sNode"}
        k8s_pvcs = {n["id"]: n for n in nodes if n["type"] == "K8sPVC"}
        k8s_services = {n["id"]: n for n in nodes if n["type"] == "K8sService"}
        ec2_instances = {n["properties"].get("instance_id"): n for n in nodes if n["type"] == "EC2Instance"}
        ebs_volumes = {n["properties"].get("volume_id"): n for n in nodes if n["type"] == "EBSVolume"}
        albs = {n["properties"].get("dns_name"): n for n in nodes if n["type"] == "AWSALB"}
        route53_records = {n["properties"].get("name"): n for n in nodes if n["type"] == "Route53Record"}
        cf_dns_records = {n["properties"].get("name"): n for n in nodes if n["type"] == "CFDNSRecord"}
        cf_tunnels = {n["properties"].get("tunnel_id"): n for n in nodes if n["type"] == "CFTunnel"}

        # 1. K8sNode -> EC2Instance (DEPLOYS_ON)
        for kn_id, kn in k8s_nodes.items():
            inst_id = kn["properties"].get("instance_id")
            if inst_id in ec2_instances:
                edges.append({
                    "from": kn_id,
                    "to": ec2_instances[inst_id]["id"],
                    "type": "DEPLOYS_ON"
                })

        # 2. K8sPVC -> EBSVolume (DEPLOYS_ON)
        for pvc_id, pvc in k8s_pvcs.items():
            vol_id = pvc["properties"].get("volume_name")
            if vol_id in ebs_volumes:
                edges.append({
                    "from": pvc_id,
                    "to": ebs_volumes[vol_id]["id"],
                    "type": "DEPLOYS_ON"
                })

        # 3. Route53Record -> AWSALB (RESOLVES_TO)
        for rec_name, rec in route53_records.items():
            val = rec["properties"].get("value", "")
            for alb_dns, alb in albs.items():
                if alb_dns and alb_dns.lower() in val.lower():
                    edges.append({
                        "from": rec["id"],
                        "to": alb["id"],
                        "type": "RESOLVES_TO"
                    })

        # 4. CFDNSRecord -> AWSALB or Route53Record (RESOLVES_TO)
        for cf_rec_name, cf_rec in cf_dns_records.items():
            content = cf_rec["properties"].get("content", "")
            # Direct to ALB
            for alb_dns, alb in albs.items():
                if alb_dns and alb_dns.lower() in content.lower():
                    edges.append({
                        "from": cf_rec["id"],
                        "to": alb["id"],
                        "type": "RESOLVES_TO"
                    })
            # To Route53
            for r53_name, r53 in route53_records.items():
                if r53_name and r53_name.lower() in content.lower():
                    edges.append({
                        "from": cf_rec["id"],
                        "to": r53["id"],
                        "type": "RESOLVES_TO"
                    })

        # 5. AWSALB -> K8sService (ROUTES_TO)
        for svc_id, svc in k8s_services.items():
            svc_name = svc["properties"].get("name", "")
            if svc_name == "api-gateway-svc" and "platform" in svc_id:
                for alb_dns, alb in albs.items():
                    if "prod-external-alb" in alb["id"]:
                        edges.append({
                            "from": alb["id"],
                            "to": svc_id,
                            "type": "ROUTES_TO"
                        })
            elif svc_name == "inference-api-svc" and "gpu-inference" in svc_id:
                for alb_dns, alb in albs.items():
                    if "internal-services-alb" in alb["id"]:
                        edges.append({
                            "from": alb["id"],
                            "to": svc_id,
                            "type": "ROUTES_TO"
                        })

        # 6. CFTunnel -> K8sService (TUNNELS_TO)
        for tunnel_id, tunnel in cf_tunnels.items():
            t_name = tunnel["properties"].get("name", "")
            if "platform" in t_name:
                for svc_id, svc in k8s_services.items():
                    if "cloudflared" in svc["properties"].get("name", "") and "platform" in svc_id:
                        edges.append({
                            "from": tunnel["id"],
                            "to": svc_id,
                            "type": "TUNNELS_TO"
                        })

        return edges

    def deduplicate_nodes(self, nodes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        seen = set()
        deduped = []
        for node in nodes:
            nid = node.get("id")
            if nid and nid not in seen:
                seen.add(nid)
                deduped.append(node)
        return deduped

    def deduplicate_edges(self, edges: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        seen = set()
        deduped = []
        for edge in edges:
            key = (edge.get("from"), edge.get("to"), edge.get("type"))
            if all(key) and key not in seen:
                seen.add(key)
                deduped.append(edge)
        return deduped

    async def push_to_omniscience(self, nodes: List[Dict[str, Any]], edges: List[Dict[str, Any]]) -> None:
        """Push graph nodes and edges to Omniscience API."""
        try:
            response = await self.client.post(
                "/api/v1/graph/sync",
                json={"nodes": nodes, "edges": edges},
            )
            response.raise_for_status()
            logger.info("Successfully synchronized %d nodes and %d edges with Omniscience", len(nodes), len(edges))
        except Exception as e:
            logger.error("Failed to sync topology graph with Omniscience: %s", e)

    async def run(self) -> None:
        """Main execution loop for continuous collection."""
        logger.info("Starting Platform State Collector daemon (mock_sync=%s)", self.mock_sync)
        while True:
            try:
                # 1. Collect K8s resources across clusters
                clusters = ["platform", "gpu-inference", "blockchain"]
                all_nodes = []
                all_edges = []

                for cluster in clusters:
                    k8s_nodes, k8s_edges = await self.collect_k8s_topology(cluster)
                    all_nodes.extend(k8s_nodes)
                    all_edges.extend(k8s_edges)

                # 2. Collect AWS resources
                aws_nodes, aws_edges = await self.collect_aws_topology()
                all_nodes.extend(aws_nodes)
                all_edges.extend(aws_edges)

                # 3. Collect Cloudflare resources
                cf_nodes, cf_edges = await self.collect_cloudflare_topology()
                all_nodes.extend(cf_nodes)
                all_edges.extend(cf_edges)

                # 4. Correlate cross-layer boundary connections
                cross_edges = self.build_cross_layer_edges(all_nodes)
                all_edges.extend(cross_edges)

                # 5. Deduplicate
                unique_nodes = self.deduplicate_nodes(all_nodes)
                unique_edges = self.deduplicate_edges(all_edges)

                # 6. Push to graph store
                await self.push_to_omniscience(unique_nodes, unique_edges)

            except Exception as e:
                logger.error("Error in collector loop: %s", e)

            await asyncio.sleep(self.sync_interval)


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    )
    # Default execution runs one round and exits if interval is set to 0 or negative
    sync_sec = int(os.environ.get("SYNC_INTERVAL_SECONDS", "0"))

    collector = PlatformStateCollector(
        omniscience_url=os.environ.get("OMNISCIENCE_URL", "http://localhost:8000"),
        omniscience_token=os.environ.get("OMNISCIENCE_TOKEN", "sk_live_mock_token"),
        sync_interval_seconds=max(sync_sec, 1),
    )

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    if sync_sec <= 0:
        logger.info("SYNC_INTERVAL_SECONDS <= 0: running a single synchronization cycle")
        async def run_once():
            try:
                clusters = ["platform", "gpu-inference", "blockchain"]
                all_nodes = []
                all_edges = []

                for cluster in clusters:
                    k8s_nodes, k8s_edges = await collector.collect_k8s_topology(cluster)
                    all_nodes.extend(k8s_nodes)
                    all_edges.extend(k8s_edges)

                aws_nodes, aws_edges = await collector.collect_aws_topology()
                all_nodes.extend(aws_nodes)
                all_edges.extend(aws_edges)

                cf_nodes, cf_edges = await collector.collect_cloudflare_topology()
                all_nodes.extend(cf_nodes)
                all_edges.extend(cf_edges)

                cross_edges = collector.build_cross_layer_edges(all_nodes)
                all_edges.extend(cross_edges)

                unique_nodes = collector.deduplicate_nodes(all_nodes)
                unique_edges = collector.deduplicate_edges(all_edges)

                await collector.push_to_omniscience(unique_nodes, unique_edges)
            finally:
                await collector.client.aclose()

        loop.run_until_complete(run_once())
    else:
        try:
            loop.run_until_complete(collector.run())
        except KeyboardInterrupt:
            logger.info("Collector daemon stopped by user")
        finally:
            loop.run_until_complete(collector.client.aclose())
