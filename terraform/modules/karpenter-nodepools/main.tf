# ---------------------------------------------------------------------------------------------------------------------
# Karpenter NodePools and EC2NodeClasses
# ---------------------------------------------------------------------------------------------------------------------
# Creates Karpenter NodePool and EC2NodeClass CRDs for each enabled pool in var.nodepool_configs.
#
# Supports both AL2023 (AWS VPC CNI) and Bottlerocket (Cilium CNI) AMI families.
# Bottlerocket is recommended for Cilium deployments due to native support and faster boot times.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "ec2_node_class" {
  for_each = { for k, v in var.nodepool_configs : k => v if v.enabled }

  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = each.key
    }
    spec = merge(
      {
        # AMI selection based on family
        amiSelectorTerms = [
          {
            alias = var.ami_family == "Bottlerocket" ? "bottlerocket@latest" : "al2023@latest"
          }
        ]
        role = var.node_iam_role_name
        subnetSelectorTerms = [
          {
            tags = {
              "karpenter.sh/discovery" = var.cluster_name
            }
          }
        ]
        securityGroupSelectorTerms = [
          {
            tags = {
              "karpenter.sh/discovery" = var.cluster_name
            }
          }
        ]
        tags = merge(
          {
            "karpenter.sh/discovery" = var.cluster_name
            "NodePool"               = each.key
          },
          var.additional_node_tags
        )
        # Block device mappings for root volume
        # Supports optional block_device_overrides for HPC workloads (io2, high IOPS)
        blockDeviceMappings = var.ami_family == "Bottlerocket" ? [
          {
            deviceName = "/dev/xvda"
            ebs = {
              volumeSize          = "4Gi"
              volumeType          = "gp3"
              encrypted           = true
              deleteOnTermination = true
            }
          },
          {
            deviceName = "/dev/xvdb"
            ebs = merge(
              {
                volumeSize          = try(each.value.block_device_overrides.volume_size, try(each.value.root_volume_size, "50Gi"))
                volumeType          = try(each.value.block_device_overrides.volume_type, "gp3")
                encrypted           = try(each.value.block_device_overrides.encrypted, true)
                deleteOnTermination = true
                iops                = try(each.value.block_device_overrides.iops, 3000)
              },
              # throughput only valid for gp3 (not io2)
              try(each.value.block_device_overrides.volume_type, "gp3") != "io2" ? {
                throughput = try(each.value.block_device_overrides.throughput, 125)
              } : {}
            )
          }
        ] : [
          {
            deviceName = "/dev/xvda"
            ebs = merge(
              {
                volumeSize          = try(each.value.block_device_overrides.volume_size, try(each.value.root_volume_size, "50Gi"))
                volumeType          = try(each.value.block_device_overrides.volume_type, "gp3")
                encrypted           = try(each.value.block_device_overrides.encrypted, true)
                deleteOnTermination = true
                iops                = try(each.value.block_device_overrides.iops, 3000)
              },
              # throughput only valid for gp3 (not io2)
              try(each.value.block_device_overrides.volume_type, "gp3") != "io2" ? {
                throughput = try(each.value.block_device_overrides.throughput, 125)
              } : {}
            )
          }
        ]
      },
      # Bottlerocket-specific settings
      var.ami_family == "Bottlerocket" ? {
        # Bottlerocket settings for Cilium
        userData = base64encode(<<-TOML
          [settings.kubernetes]
          cluster-name = "${var.cluster_name}"

          [settings.kubernetes.node-labels]
          "karpenter.sh/nodepool" = "${each.key}"

          [settings.kubernetes.node-taints]
          ${join("\n", [for t in try(each.value.taints, []) : "\"${t.key}\" = \"${t.value}:${t.effect}\""])}
          TOML
        )
      } : {},
      # HPC placement group and AZ pinning (optional)
      try(each.value.placement_group_name, null) != null || try(each.value.availability_zone, null) != null ? {
        placement = merge(
          try(each.value.placement_group_name, null) != null ? { placementGroupName = each.value.placement_group_name } : {},
          try(each.value.availability_zone, null) != null ? { availabilityZone = each.value.availability_zone } : {}
        )
      } : {}
    )
  }
}

resource "kubernetes_manifest" "node_pool" {
  for_each = { for k, v in var.nodepool_configs : k => v if v.enabled }

  depends_on = [kubernetes_manifest.ec2_node_class]

  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = each.key
    }
    spec = {
      template = {
        metadata = {
          labels = merge(
            {
              "nodepool" = each.key
            },
            try(each.value.labels, {})
          )
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = each.key
          }
          requirements = concat(
            [
              {
                key      = "karpenter.sh/capacity-type"
                operator = "In"
                values   = each.value.spot_percentage >= 100 ? ["spot"] : each.value.spot_percentage <= 0 ? ["on-demand"] : ["spot", "on-demand"]
              },
              {
                key      = "kubernetes.io/arch"
                operator = "In"
                values   = try(each.value.architectures, ["amd64"])
              },
              {
                key      = "kubernetes.io/os"
                operator = "In"
                values   = ["linux"]
              }
            ],
            # Instance families filter
            length(try(each.value.instance_families, [])) > 0 ? [
              {
                key      = "karpenter.k8s.aws/instance-family"
                operator = "In"
                values   = each.value.instance_families
              }
            ] : [],
            # Instance sizes filter
            length(try(each.value.instance_sizes, [])) > 0 ? [
              {
                key      = "karpenter.k8s.aws/instance-size"
                operator = "In"
                values   = each.value.instance_sizes
              }
            ] : [],
            # Exclude certain instance types
            length(try(each.value.excluded_instance_types, [])) > 0 ? [
              {
                key      = "node.kubernetes.io/instance-type"
                operator = "NotIn"
                values   = each.value.excluded_instance_types
              }
            ] : []
          )
          # Taints
          taints = try(each.value.taints, [])
          # Startup taints (removed once node is ready)
          startupTaints = try(each.value.startup_taints, [])
          # Expire nodes after a certain duration
          expireAfter = try(each.value.expire_after, "720h") # 30 days default
        }
      }
      limits = {
        cpu    = tostring(each.value.cpu_limit)
        memory = "${each.value.memory_limit}Gi"
      }
      disruption = {
        consolidationPolicy = each.value.consolidation_policy
        consolidateAfter    = each.value.consolidate_after
        # Budget controls how many nodes can be disrupted at once
        budgets = try(each.value.disruption_budgets, [
          {
            nodes = "10%"
          }
        ])
      }
      weight = try(each.value.weight, 10)
    }
  }
}
