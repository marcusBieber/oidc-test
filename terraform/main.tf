terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  } 
}

provider "aws" {
  region = "eu-central-1"
}

resource "aws_s3_bucket" "oidc_test" {
  bucket_prefix = "marcus-oidc-test-"

  tags = {
    Name      = "GitHub OIDC Terraform Test"
    ManagedBy = "Terraform"
  }
}

output "bucket_name" {
  value = aws_s3_bucket.oidc_test.bucket
}
