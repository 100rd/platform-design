# -----------------------------------------------------------------------------
# ecr-pull-through-cache — input variables (ADR-0029)
# -----------------------------------------------------------------------------

variable "upstreams" {
  description = <<-EOT
    Map of upstream public registries to mirror via ECR Pull-Through Cache.
    The map key is the local `ecr_repository_prefix` callers pull under
    (e.g. `docker-hub`, `quay`, `ghcr`, `k8s`, `ecr-public`). Callers then
    reference images as
    `<acct>.dkr.ecr.<region>.amazonaws.com/<prefix>/<upstream-image>`.

    Fields:
      - upstream_registry_url: the upstream registry endpoint
          (public.ecr.aws, registry-1.docker.io, quay.io, ghcr.io,
           registry.k8s.io, registry.gitlab.com).
      - requires_credential: true for registries that AWS requires an upstream
          credential for (Docker Hub). When true, a Secrets Manager secret named
          `ecr-pullthroughcache/<key>` is created and wired as `credential_arn`.
  EOT

  type = map(object({
    upstream_registry_url = string
    requires_credential   = optional(bool, false)
  }))

  default = {
    ecr-public = {
      upstream_registry_url = "public.ecr.aws"
    }
    docker-hub = {
      upstream_registry_url = "registry-1.docker.io"
      requires_credential   = true
    }
    quay = {
      upstream_registry_url = "quay.io"
    }
    ghcr = {
      upstream_registry_url = "ghcr.io"
    }
    k8s = {
      upstream_registry_url = "registry.k8s.io"
    }
  }

  validation {
    condition = alltrue([
      for k, v in var.upstreams : contains(
        [
          "public.ecr.aws",
          "registry-1.docker.io",
          "quay.io",
          "ghcr.io",
          "registry.k8s.io",
          "registry.gitlab.com",
        ],
        v.upstream_registry_url
      )
    ])
    error_message = "upstream_registry_url must be a supported ECR PTC upstream: public.ecr.aws, registry-1.docker.io, quay.io, ghcr.io, registry.k8s.io, registry.gitlab.com."
  }
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK used to encrypt cache repositories created by the repository creation template. Required because the template uses KMS encryption and resource tags, which force a custom IAM role."
  type        = string
  default     = null
}

variable "create_repository_creation_template" {
  description = "Whether to create an aws_ecr_repository_creation_template that auto-configures cached repos (KMS encryption, lifecycle, immutable tags) on first pull."
  type        = bool
  default     = true
}

variable "create_registry_scanning_configuration" {
  description = "Whether to manage the registry-level scanning configuration so cached repositories are scanned on push. The registry scanning config is a singleton per registry; disable if another unit already owns it."
  type        = bool
  default     = true
}

variable "scan_type" {
  description = "ECR registry scan type for cached repositories. ENHANCED uses Amazon Inspector; BASIC uses the built-in scanner."
  type        = string
  default     = "ENHANCED"

  validation {
    condition     = contains(["BASIC", "ENHANCED"], var.scan_type)
    error_message = "scan_type must be either BASIC or ENHANCED."
  }
}

variable "image_tag_mutability" {
  description = "Tag mutability for cached repositories created by the template."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "max_image_count" {
  description = "Maximum number of tagged images to retain per cached repository before the lifecycle policy expires the oldest."
  type        = number
  default     = 50
}

variable "untagged_expiry_days" {
  description = "Number of days after which untagged images in cached repositories are expired."
  type        = number
  default     = 7
}

variable "dockerhub_secret_placeholder" {
  description = <<-EOT
    Placeholder value seeded into the Docker Hub upstream credential secret.
    The real value (JSON { "username": "...", "accessToken": "..." }) MUST be
    injected out-of-band (e.g. via External Secrets Operator / a secure
    pipeline) and is NOT stored in version control. The lifecycle
    ignore_changes on secret_string prevents Terraform from clobbering the
    rotated value on subsequent applies.
  EOT
  type        = string
  default     = "{\"username\":\"REPLACE_ME\",\"accessToken\":\"REPLACE_ME\"}"
  sensitive   = true
}

variable "recovery_window_in_days" {
  description = "Recovery window for the Docker Hub credential Secrets Manager secret. 0 forces immediate deletion (use only in ephemeral/test accounts)."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}
