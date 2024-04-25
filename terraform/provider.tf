terraform {
  required_version = "~> 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.46.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.1"
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
