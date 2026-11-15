terraform {
  required_version = ">= 1.11.0"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 1.4"
    }
  }
}
