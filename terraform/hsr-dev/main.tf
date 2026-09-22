terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

module "demo_app" {
  source = "../modules/ecs-demo-app"

  environment = "dev"

  # dev bewusst auf Sparflamme: 1 Task je Service, kleinste Fargate-Größe.
  desired_count    = 1
  container_cpu    = 256
  container_memory = 512
}

output "demo_app_url" {
  value = module.demo_app.alb_dns_name
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
