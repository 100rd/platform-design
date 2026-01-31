# ---------------------------------------------------------------------------------------------------------------------
# Karpenter NodePools and EC2NodeClasses
# ---------------------------------------------------------------------------------------------------------------------
# Creates Karpenter NodePool and EC2NodeClass CRDs for each enabled pool in var.nodepool_configs.
# ---------------------------------------------------------------------------------------------------------------------

resource "kubernetes_manifest" "ec2_node_class" {
  for_each = { for k, v in var.nodepool_configs : k => v if v.enabled }

  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = each.key
    }
    spec = {
      amiSelectorTerms = [
        {
          alias = "al2023@latest"
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
      tags = {
        "karpenter.sh/discovery" = var.cluster_name
        "NodePool"               = each.key
      }
    }
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
          labels = {
            "nodepool" = each.key
          }
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
              }
            ],
            length(try(each.value.instance_families, [])) > 0 ? [
              {
                key      = "karpenter.k8s.aws/instance-family"
                operator = "In"
                values   = each.value.instance_families
              }
            ] : []
          )
        }
      }
      limits = {
        cpu    = tostring(each.value.cpu_limit)
        memory = "${each.value.memory_limit}Gi"
      }
      disruption = {
        consolidationPolicy = each.value.consolidation_policy
        consolidateAfter    = each.value.consolidate_after
      }
      weight = try(each.value.weight, 10)
    }
  }
}
