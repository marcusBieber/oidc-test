#!/usr/bin/env bash

set -euo pipefail

BOOTSTRAP_BUCKET="marcus-bootstrap-tfstate-798836978111"
REGION="eu-central-1"

echo "Prüfe AWS Identität..."
aws sts get-caller-identity

echo "Erstelle Bootstrap-State-Bucket..."
aws s3api create-bucket \
  --bucket "${BOOTSTRAP_BUCKET}" \
  --region "${REGION}" \
  --create-bucket-configuration LocationConstraint="${REGION}"

echo "Aktiviere Versioning..."
aws s3api put-bucket-versioning \
  --bucket "${BOOTSTRAP_BUCKET}" \
  --versioning-configuration Status=Enabled

echo "Aktiviere SSE-S3 Verschlüsselung..."
aws s3api put-bucket-encryption \
  --bucket "${BOOTSTRAP_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

echo "Blockiere öffentlichen Zugriff..."
aws s3api put-public-access-block \
  --bucket "${BOOTSTRAP_BUCKET}" \
  --public-access-block-configuration \
'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

echo "Initialisiere Bootstrap Terraform..."
terraform -chdir=terraform/bootstrap init -reconfigure

echo "Terraform Plan..."
terraform -chdir=terraform/bootstrap plan

echo "Terraform Apply..."
terraform -chdir=terraform/bootstrap apply
