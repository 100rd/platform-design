# ---------------------------------------------------------------------------------------------------------------------
# GPU Video Analysis Stack Template
# ---------------------------------------------------------------------------------------------------------------------
# Composable stack that deploys the GPU video analysis infrastructure:
#
#   Compute Layer:
#     gpu-vpc → gpu-placement-group → gpu-eks → gpu-cilium
#                                              → gpu-karpenter-iam → gpu-karpenter-controller
#                                                                   → gpu-karpenter-nodepools
#   Data Layer:
#     gpu-s3-raw-video ──→ gpu-eventbridge-video (requires gpu-sqs-video-jobs)
#     gpu-s3-processing
#     gpu-s3-results ────→ gpu-cloudfront
#     gpu-sqs-video-jobs
#     gpu-dynamodb-jobs
#     gpu-elasticache (requires gpu-vpc + gpu-eks)
#
# Optimized for real-time video analysis: GPU instances (A10G/T4), placement groups
# for low-latency networking, S3 storage tiers, SQS job queue, CloudFront delivery.
#
# CNI: Cilium with ENI IPAM mode
# AMI: Bottlerocket (native Cilium support)
#
# Usage (from live tree):
#   cd terragrunt/staging/eu-west-3/gpu-analysis
#   terragrunt stack plan
#   terragrunt stack apply
# ---------------------------------------------------------------------------------------------------------------------

# =============================================================================
# Compute Layer
# =============================================================================

unit "gpu-vpc" {
  source = "${get_repo_root()}/catalog/units/gpu-vpc"
  path   = "gpu-vpc"
}

unit "gpu-placement-group" {
  source = "${get_repo_root()}/catalog/units/gpu-placement-group"
  path   = "gpu-placement-group"
}

unit "gpu-eks" {
  source = "${get_repo_root()}/catalog/units/gpu-eks"
  path   = "gpu-eks"
}

unit "gpu-cilium" {
  source = "${get_repo_root()}/catalog/units/gpu-cilium"
  path   = "gpu-cilium"
}

unit "gpu-karpenter-iam" {
  source = "${get_repo_root()}/catalog/units/gpu-karpenter-iam"
  path   = "gpu-karpenter-iam"
}

unit "gpu-karpenter-controller" {
  source = "${get_repo_root()}/catalog/units/gpu-karpenter-controller"
  path   = "gpu-karpenter-controller"
}

unit "gpu-karpenter-nodepools" {
  source = "${get_repo_root()}/catalog/units/gpu-karpenter-nodepools"
  path   = "gpu-karpenter-nodepools"
}

# =============================================================================
# Data Layer — Storage
# =============================================================================

unit "gpu-s3-raw-video" {
  source = "${get_repo_root()}/catalog/units/gpu-s3-raw-video"
  path   = "gpu-s3-raw-video"
}

unit "gpu-s3-processing" {
  source = "${get_repo_root()}/catalog/units/gpu-s3-processing"
  path   = "gpu-s3-processing"
}

unit "gpu-s3-results" {
  source = "${get_repo_root()}/catalog/units/gpu-s3-results"
  path   = "gpu-s3-results"
}

# =============================================================================
# Data Layer — Queue & Events
# =============================================================================

unit "gpu-sqs-video-jobs" {
  source = "${get_repo_root()}/catalog/units/gpu-sqs-video-jobs"
  path   = "gpu-sqs-video-jobs"
}

unit "gpu-eventbridge-video" {
  source = "${get_repo_root()}/catalog/units/gpu-eventbridge-video"
  path   = "gpu-eventbridge-video"
}

# =============================================================================
# Data Layer — Metadata & Cache
# =============================================================================

unit "gpu-dynamodb-jobs" {
  source = "${get_repo_root()}/catalog/units/gpu-dynamodb-jobs"
  path   = "gpu-dynamodb-jobs"
}

unit "gpu-elasticache" {
  source = "${get_repo_root()}/catalog/units/gpu-elasticache"
  path   = "gpu-elasticache"
}

# =============================================================================
# Data Layer — Delivery
# =============================================================================

unit "gpu-cloudfront" {
  source = "${get_repo_root()}/catalog/units/gpu-cloudfront"
  path   = "gpu-cloudfront"
}
