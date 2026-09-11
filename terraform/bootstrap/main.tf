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

resource "aws_iam_openid_connect_provider" "github" {
  url = var.github_oidc_provider_url

  client_id_list = [
    "sts.amazonaws.com"
  ]
}

locals {
  # AWS benennt die Condition-Keys im Trust-Dokument nach dem Host des
  # registrierten OIDC-Providers (ohne Schema) - muss daher bei GHES
  # (abweichender Host) mitwandern, sonst greift die Condition nie.
  oidc_condition_namespace = replace(var.github_oidc_provider_url, "https://", "")

  github_owner_part = var.github_owner_id != null ? "${var.github_owner}@${var.github_owner_id}" : var.github_owner
  github_repo_part  = var.github_repo_id != null ? "${var.github_repo}@${var.github_repo_id}" : var.github_repo
}

data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_condition_namespace}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_condition_namespace}:sub"
      values   = ["repo:${local.github_owner_part}/${local.github_repo_part}:ref:refs/heads/${var.github_branch}"]
    }

    dynamic "condition" {
      for_each = var.github_repo_id_ghes != null ? [var.github_repo_id_ghes] : []

      content {
        test     = "StringEquals"
        variable = "${local.oidc_condition_namespace}:repository_id"
        values   = [condition.value]
      }
    }
  }
}

resource "aws_iam_role" "github_oidc_test" {
  name = "github-oidc-test"

  assume_role_policy = data.aws_iam_policy_document.github_oidc_trust.json

  description = "GitHub Actions OIDC test role"
}

resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.github_oidc_test.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_s3_bucket" "infrastructure_state" {
  bucket = "marcus-infrastructure-tfstate-798836978111"

  tags = {
    Name      = "Infrastructure Terraform State"
    ManagedBy = "Terraform Bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "infrastructure_state" {
  bucket = aws_s3_bucket.infrastructure_state.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "infrastructure_state" {
  bucket = aws_s3_bucket.infrastructure_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "infrastructure_state" {
  bucket = aws_s3_bucket.infrastructure_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
