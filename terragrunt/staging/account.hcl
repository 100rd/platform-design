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
  enable_tgw_attachment = false # Enable once TGW is deployed in network account
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
    }
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
