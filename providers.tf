terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" {
  region                   = var.aws_region
  shared_credentials_files = [var.aws_credential_path]
  profile                  = var.aws_user
}