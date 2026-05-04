# -----------------------------------------------------------------------------
# state-backend-dr — basic example used for `terraform validate`
#
# This is a non-deployable harness. It wires up the two providers the module
# requires and points at fake source-bucket inputs. Do NOT `terraform apply`
# this example; it exists so CI can validate the module syntactically.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

provider "aws" {
  region                      = "eu-west-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  access_key                  = "validate-only"
  secret_key                  = "validate-only"
}

provider "aws" {
  alias                       = "dr"
  region                      = "eu-central-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  access_key                  = "validate-only"
  secret_key                  = "validate-only"
}

module "state_backend_dr" {
  source = "../.."

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  account_name   = "dev"
  primary_region = "eu-west-1"
  dr_region      = "eu-central-1"

  source_bucket_id      = "tfstate-dev-eu-west-1"
  source_bucket_arn     = "arn:aws:s3:::tfstate-dev-eu-west-1"
  source_lock_table_arn = "arn:aws:dynamodb:eu-west-1:111111111111:table/terraform-locks-dev"
}
