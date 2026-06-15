# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-managed-nodegroup — reserved EFA-DRA training node group (ADR-0046 D2/D4, ADR-0045 D3)
# ---------------------------------------------------------------------------------------------------------------------
# The narrow managed-node-group path for large, reserved-capacity distributed training
# that wants the EFA DRA topology model (the ONLY place the EFA DRA driver works —
# Karpenter cannot run it, ADR-0045 D2/D3). Everything else stays on Karpenter
# (aws-eks-gpu-nodepools).
#
# Capacity: ON_DEMAND or a CAPACITY_BLOCK reservation (ADR-0046 D4) — NEVER spot for
# gang training (ADR-0046 A4). EFA NICs are exposed via DRA (efa_mode = dra); the
# aws-eks-efa-fabric module ships the netdev DeviceClass/ResourceClaimTemplate.
#
# Default-OFF (var.enabled). ADR-0028 platform:* tags on every resource.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  create = var.enabled

  base_tags = merge(
    {
      "platform:system"     = "ml-platform"
      "platform:component"  = "gpu-compute"
      "platform:managed-by" = "terragrunt"
    },
    var.tags,
    {
      "platform:efa-mode" = var.efa_mode
      "platform:capacity" = lower(var.capacity_type)
    },
  )

  node_labels = merge(
    {
      "platform.system"    = "ml-platform"
      "platform.component" = "gpu-compute"
      "nvidia.com/gpu"     = "present"
      "efa.enabled"        = tostring(var.enable_efa)
      "training.reserved"  = "true"
    },
    var.labels,
  )

  # Create a minimal node role only when the caller does not supply one.
  create_role = local.create && var.node_role_arn == ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Optional minimal node IAM role (when the caller does not pass node_role_arn).
# ---------------------------------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume" {
  count = local.create_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  count = local.create_role ? 1 : 0

  name               = "${var.cluster_name}-gpu-training-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume[0].json

  tags = local.base_tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.create_role ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]) : toset([])

  role       = aws_iam_role.node[0].name
  policy_arn = each.value
}

# ---------------------------------------------------------------------------------------------------------------------
# The EKS managed node group — reserved EFA-DRA training (ADR-0046 D2).
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_eks_node_group" "training" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  node_group_name = "${var.cluster_name}-gpu-training"
  node_role_arn   = var.node_role_arn != "" ? var.node_role_arn : aws_iam_role.node[0].arn
  subnet_ids      = var.subnet_ids

  instance_types = [var.instance_type]
  ami_type       = var.ami_type
  capacity_type  = var.capacity_type

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  labels = local.node_labels

  # GPU + training taints so only GPU training jobs land here.
  taint {
    key    = "nvidia.com/gpu"
    value  = "present"
    effect = "NO_SCHEDULE"
  }

  taint {
    key    = "training-reserved"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = merge(local.base_tags, {
    "platform:capacity-block-id" = var.capacity_block_reservation_id
    "placement-group"            = var.placement_group_name
  })

  lifecycle {
    # The reserved pool is pinned for the duration of a run; ignore desired_size
    # drift from external scaling so a job's nodes are not disrupted mid-NCCL.
    ignore_changes = [scaling_config[0].desired_size]
  }
}
