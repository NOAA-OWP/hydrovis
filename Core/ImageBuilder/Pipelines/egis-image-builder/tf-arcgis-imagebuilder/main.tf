terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
  #profile = "nwc-dev"
}

locals {
  arcgisVersionName = replace(var.arcgisenterprise_version, ".", "-")
}

data "aws_region" "current" {}
