locals {
  account_name   = "staging"
  account_id     = "222222222222" # TODO: Replace with actual AWS account ID
  aws_account_id = "222222222222" # Alias for reference compatibility
  environment    = "staging"

  # Organization context
  org_account_type   = "workload"
  org_ou             = "NonProd"
  management_account = "000000000000"
  network_account    = "555555555555"

  # Transit Gateway connectivity (shared via RAM from network account)
  enable_tgw_attachment = true  # Enabled for multi-region connectivity
  transit_gateway_id    = ""    # Populate after network account deployment
  tgw_route_table_id    = ""    # nonprod route table ID from network account

  single_nat_gateway    = false
  eks_public_access     = false
  eks_instance_types    = ["m6i.xlarge"]
  eks_min_size          = 2
  eks_max_size          = 5
  eks_desired_size      = 3
  rds_instance_class    = "db.r6g.large"
  rds_allocated_storage = 50
  rds_multi_az          = true
  monitoring_replicas   = 2

  # --- Scaling stack ---
  karpenter_controller_replicas = 2
  karpenter_log_level           = "info"
  enable_keda                   = true
  keda_operator_replicas        = 2
  keda_metrics_server_replicas  = 2
  enable_hpa_defaults           = true
  enable_wpa                    = false

  # --- Cilium ---
  cilium_replace_kube_proxy = false

  # --- ClusterMesh (multi-region) ---
  enable_clustermesh = true
  clustermesh_cluster_ids = {
    "eu-west-1"    = 1
    "eu-central-1" = 2
    "eu-west-2"    = 3  # Reserved for future
    "eu-west-3"    = 4  # Reserved for future
  }
  clustermesh_apiserver_replicas = 2
  peer_vpc_cidrs = {
    "eu-west-1"    = "10.10.0.0/16"
    "eu-central-1" = "10.13.0.0/16"
  }

  # --- External traffic (multi-region) ---
  enable_nlb_ingress        = true
  enable_global_accelerator = true

  # --- Secrets Management (multi-region replication) ---
  # Secrets are created in the primary region and replicated to all replica regions.
  # Each replica is encrypted with the region-specific KMS CMK for secrets-manager.
  # replica_kms_key_arns: populate with actual KMS key ARNs after deploying KMS in each region.
  secrets_config = {
    primary_region = "eu-central-1"
    replica_regions = ["eu-west-1", "eu-west-2", "eu-west-3"]
    rotation_days  = 90
    replica_kms_key_arns = {
      "eu-west-1" = "" # TODO: Set to KMS secrets-manager key ARN from eu-west-1 after deployment
      "eu-west-2" = "" # TODO: Set to KMS secrets-manager key ARN from eu-west-2 after deployment
      "eu-west-3" = "" # TODO: Set to KMS secrets-manager key ARN from eu-west-3 after deployment
    }
  }

  # ===========================================================================
  # Blockchain HPC Cluster Configuration
  # ===========================================================================
  # Dedicated EKS cluster for Ethereum workloads: execution clients, consensus
  # clients, and MEV trading. Uses placement groups for low-latency networking,
  # Nitro/ENA-optimized instances, and on-demand-only capacity.
  # ===========================================================================
  blockchain_config = {
    # --- EKS system node group sizing ---
    eks_instance_types = ["m6i.xlarge"]
    eks_min_size       = 2
    eks_max_size       = 4
    eks_desired_size   = 2

    # --- Cilium ---
    cilium_replace_kube_proxy = false

    # --- Karpenter controller ---
    karpenter_controller_replicas = 2
    karpenter_log_level           = "info"
    karpenter_ami_family          = "Bottlerocket"

    # --- Placement groups ---
    placement_groups = {
      hpc = {
        name     = "staging-euc1-blockchain-hpc"
        strategy = "cluster"
      }
    }

    # --- Karpenter NodePools (HPC-optimized for Ethereum) ---
    karpenter_nodepools = {

      # -----------------------------------------------------------------------
      # Execution Clients — Geth, Nethermind, Besu
      # High-bandwidth Nitro instances for block propagation and P2P gossip.
      # -----------------------------------------------------------------------
      execution-clients = {
        enabled           = true
        cpu_limit         = 200
        memory_limit      = 800
        spot_percentage   = 0 # On-demand only — slashing risk
        instance_families = ["c5n", "c6in", "r5n", "r6in"]
        instance_sizes    = ["2xlarge", "4xlarge", "8xlarge"]
        architectures     = ["amd64"]

        # HPC placement
        placement_group_name = "staging-euc1-blockchain-hpc"
        availability_zone    = "eu-central-1a"

        # High-performance storage for chain state
        block_device_overrides = {
          volume_type = "gp3"
          volume_size = "500Gi"
          iops        = 16000
          throughput  = 1000
          encrypted   = true
        }

        # Conservative disruption — never disrupt during business hours
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "300s"
        disruption_budgets = [
          { nodes = "0", schedule = "0 9 * * 1-5", duration = "10h" },
          { nodes = "1" }
        ]

        labels = {
          "blockchain.io/role"    = "execution"
          "blockchain.io/network" = "ethereum"
        }
        taints = [
          { key = "blockchain.io/role", value = "execution", effect = "NoSchedule" }
        ]

        expire_after = "2160h" # 90 days — long-lived
        weight       = 10
      }

      # -----------------------------------------------------------------------
      # Consensus Clients — Prysm, Lighthouse, Teku
      # Network-optimized instances for attestation and beacon chain duties.
      # -----------------------------------------------------------------------
      consensus-clients = {
        enabled           = true
        cpu_limit         = 100
        memory_limit      = 400
        spot_percentage   = 0 # On-demand only — slashing risk
        instance_families = ["c5n", "c6in"]
        instance_sizes    = ["xlarge", "2xlarge", "4xlarge"]
        architectures     = ["amd64"]

        # HPC placement
        placement_group_name = "staging-euc1-blockchain-hpc"
        availability_zone    = "eu-central-1a"

        # Storage for beacon chain state
        block_device_overrides = {
          volume_type = "gp3"
          volume_size = "200Gi"
          iops        = 10000
          throughput  = 750
          encrypted   = true
        }

        # Very conservative disruption
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "600s"
        disruption_budgets = [
          { nodes = "0", schedule = "0 9 * * 1-5", duration = "10h" },
          { nodes = "1" }
        ]

        labels = {
          "blockchain.io/role"    = "consensus"
          "blockchain.io/network" = "ethereum"
        }
        taints = [
          { key = "blockchain.io/role", value = "consensus", effect = "NoSchedule" }
        ]

        expire_after = "2160h" # 90 days
        weight       = 10
      }

      # -----------------------------------------------------------------------
      # MEV Trading — MEV bots, searchers, block builders
      # Ultra-low-latency instances with NVMe local storage for state access.
      # -----------------------------------------------------------------------
      mev-trading = {
        enabled           = true
        cpu_limit         = 100
        memory_limit      = 400
        spot_percentage   = 0 # On-demand only — latency-critical
        instance_families = ["c5n", "c6in", "i3en"]
        instance_sizes    = ["2xlarge", "4xlarge"]
        architectures     = ["amd64"]

        # HPC placement
        placement_group_name = "staging-euc1-blockchain-hpc"
        availability_zone    = "eu-central-1a"

        # io2 Block Express — lowest latency EBS
        block_device_overrides = {
          volume_type = "io2"
          volume_size = "200Gi"
          iops        = 64000
          encrypted   = true
        }

        # Never auto-disrupt MEV nodes
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "Never"
        disruption_budgets = [
          { nodes = "0" }
        ]

        labels = {
          "blockchain.io/role"    = "mev-trading"
          "blockchain.io/network" = "ethereum"
        }
        taints = [
          { key = "blockchain.io/role", value = "mev-trading", effect = "NoSchedule" }
        ]

        expire_after = "2160h" # 90 days
        weight       = 5       # Highest priority (lowest weight)
      }

      # -----------------------------------------------------------------------
      # Bitcoin Full Nodes — Bitcoin Core archive nodes
      # Memory-optimized instances for UTXO set (~15GB), 2TB storage for
      # full blockchain. No placement group needed (P2P is global).
      # 2 replicas with RPC load balancing.
      # -----------------------------------------------------------------------
      bitcoin-full-nodes = {
        enabled           = true
        cpu_limit         = 32
        memory_limit      = 128
        spot_percentage   = 0          # On-demand — chain sync takes 5-7 days
        instance_families = ["r6i", "r7i", "r6a"]  # Memory-optimized for UTXO set
        instance_sizes    = ["2xlarge", "4xlarge"]  # 8-16 vCPU, 64-128GB RAM
        architectures     = ["amd64"]

        # No placement group — Bitcoin P2P is global, no latency benefit
        # Multi-AZ for resilience

        # 2TB gp3 for full blockchain (~700GB) + growth headroom
        block_device_overrides = {
          volume_type = "gp3"
          volume_size = "2000Gi"
          iops        = 16000
          throughput  = 1000
          encrypted   = true
        }

        # Never auto-disrupt — sync is expensive to repeat
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "Never"
        disruption_budgets = [
          { nodes = "0" }  # Zero disruption
        ]

        labels = {
          "blockchain.io/role"    = "bitcoin-full-node"
          "blockchain.io/network" = "bitcoin"
        }
        taints = [
          { key = "blockchain.io/role", value = "bitcoin-full-node", effect = "NoSchedule" }
        ]

        expire_after = "2160h" # 90 days
        weight       = 10
      }
    }
  }

  # ===========================================================================
  # GPU Video Analysis Cluster Configuration
  # ===========================================================================
  # Dedicated EKS cluster for real-time video analysis of sport game temperature
  # maps. Uses GPU instances (NVIDIA A10G for inference, T4 for preprocessing)
  # with placement groups for low-latency networking.
  # ===========================================================================
  gpu_analysis_config = {
    # --- EKS system node group sizing ---
    eks_instance_types = ["m6i.large"]
    eks_min_size       = 2
    eks_max_size       = 3
    eks_desired_size   = 2

    # --- Cilium ---
    cilium_replace_kube_proxy = false

    # --- Karpenter controller ---
    karpenter_controller_replicas = 2
    karpenter_log_level           = "info"
    karpenter_ami_family          = "Bottlerocket"

    # --- Placement groups ---
    placement_groups = {
      gpu-cluster = {
        name     = "staging-euw3-gpu-analysis-cluster"
        strategy = "cluster"
      }
    }

    # --- Karpenter NodePools (GPU-optimized for video analysis) ---
    karpenter_nodepools = {

      # -----------------------------------------------------------------------
      # GPU Inference — Real-time video analysis (NVIDIA A10G)
      # On-demand only for SLA guarantees.
      # -----------------------------------------------------------------------
      gpu-inference = {
        enabled           = true
        cpu_limit         = 100
        memory_limit      = 400
        spot_percentage   = 0          # On-demand — real-time SLA
        instance_families = ["g5"]     # NVIDIA A10G (24GB VRAM)
        instance_sizes    = ["xlarge", "2xlarge", "4xlarge"]
        architectures     = ["amd64"]

        # Single-AZ placement for GPU cluster locality
        placement_group_name = "staging-euw3-gpu-analysis-cluster"
        availability_zone    = "eu-west-3a"

        # High-performance storage for video frames and model weights
        block_device_overrides = {
          volume_type = "gp3"
          volume_size = "300Gi"
          iops        = 10000
          throughput  = 750
          encrypted   = true
        }

        # Conservative disruption — never disrupt during business hours
        consolidation_policy = "WhenEmpty"
        consolidate_after    = "300s"
        disruption_budgets = [
          { nodes = "0", schedule = "0 9 * * 1-5", duration = "10h" },
          { nodes = "1" }
        ]

        labels = {
          "gpu.nvidia.com/class" = "inference"
          "gpu.nvidia.com/type"  = "a10g"
          "workload.io/type"     = "video-analysis"
        }
        taints = [
          { key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }
        ]

        expire_after = "1440h"  # 60 days
        weight       = 10
      }

      # -----------------------------------------------------------------------
      # GPU Preprocessing — Video decode, frame extraction (NVIDIA T4)
      # 70% spot for cost optimization on batch workloads.
      # -----------------------------------------------------------------------
      gpu-preprocessing = {
        enabled           = true
        cpu_limit         = 100
        memory_limit      = 400
        spot_percentage   = 70         # Cost optimization for batch work
        instance_families = ["g4dn"]   # NVIDIA T4 (16GB VRAM)
        instance_sizes    = ["xlarge", "2xlarge", "4xlarge"]
        architectures     = ["amd64"]

        # Single-AZ placement for GPU cluster locality
        placement_group_name = "staging-euw3-gpu-analysis-cluster"
        availability_zone    = "eu-west-3a"

        # Storage for video decode buffers
        block_device_overrides = {
          volume_type = "gp3"
          volume_size = "200Gi"
          iops        = 5000
          throughput  = 500
          encrypted   = true
        }

        # Moderate disruption tolerance
        consolidation_policy = "WhenEmptyOrUnderutilized"
        consolidate_after    = "180s"

        labels = {
          "gpu.nvidia.com/class" = "preprocessing"
          "gpu.nvidia.com/type"  = "t4"
          "workload.io/type"     = "video-preprocessing"
        }
        taints = [
          { key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }
        ]

        expire_after = "720h"   # 30 days
        weight       = 20
      }

      # -----------------------------------------------------------------------
      # CPU Coordination — Orchestration, API serving
      # 80% spot, no GPU taint.
      # -----------------------------------------------------------------------
      cpu-coordination = {
        enabled           = true
        cpu_limit         = 100
        memory_limit      = 200
        spot_percentage   = 80
        instance_families = ["c6i", "c6a", "m6i"]
        instance_sizes    = ["xlarge", "2xlarge"]
        architectures     = ["amd64"]

        # Aggressive consolidation for stateless coordination pods
        consolidation_policy = "WhenEmptyOrUnderutilized"
        consolidate_after    = "60s"

        labels = {
          "workload.io/type" = "coordination"
        }

        expire_after = "720h"   # 30 days
        weight       = 30
      }
    }
  }

  # ===========================================================================
  # GPU Video Pipeline Configuration
  # ===========================================================================
  # Data infrastructure for the video analysis pipeline: storage, queuing,
  # metadata, caching, and delivery.
  # ===========================================================================
  video_pipeline_config = {
    # --- ElastiCache Redis ---
    redis_engine_version = "7.1"
    redis_node_type      = "cache.t4g.micro"   # Small for staging
    redis_num_nodes      = 2                     # Multi-AZ

    # --- CloudFront ---
    cloudfront_price_class    = "PriceClass_100"  # EU + NA only
    cloudfront_allowed_countries = ["FR", "DE", "GB", "ES", "IT", "NL", "BE", "AT", "CH", "PT"]
  }

  # ===========================================================================
  # Platform Karpenter NodePools (existing — unchanged)
  # ===========================================================================
  karpenter_nodepools = {
    x86 = {
      enabled              = true
      cpu_limit            = 500
      memory_limit         = 1000
      spot_percentage      = 80
      instance_families    = ["m6i", "m6a", "m5", "m5a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "60s"
      weight               = 10
    }
    arm64 = {
      enabled              = true
      cpu_limit            = 300
      memory_limit         = 600
      spot_percentage      = 85
      instance_families    = ["m6g", "m7g", "c6g", "c7g"]
      architectures        = ["arm64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "60s"
      weight               = 20
    }
    c-series = {
      enabled              = true
      cpu_limit            = 200
      memory_limit         = 400
      spot_percentage      = 70
      instance_families    = ["c6i", "c6a", "c5", "c5a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "60s"
      weight               = 30
    }
    spot-flexible = {
      enabled              = true
      cpu_limit            = 200
      memory_limit         = 400
      spot_percentage      = 100
      instance_families    = ["m6i", "m6a", "m5", "c6i", "c6a", "r6i", "r6a"]
      architectures        = ["amd64"]
      consolidation_policy = "WhenEmptyOrUnderutilized"
      consolidate_after    = "60s"
      weight               = 40
    }
  }
}
