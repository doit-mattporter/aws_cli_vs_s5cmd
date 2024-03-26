terraform {
  required_version = "~> 1.7.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.41.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

provider "aws" {
  region = var.same_region_benchmark_region
}

provider "aws" {
  alias  = "other_region"
  region = var.other_region_benchmark_region
}

provider "random" {}
