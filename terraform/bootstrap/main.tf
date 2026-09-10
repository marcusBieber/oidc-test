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
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]
}

data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.github.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:marcusBieber@180164030/oidc-test@1361295306:ref:refs/heads/main"
      ]
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
    status = "Enabled"
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


