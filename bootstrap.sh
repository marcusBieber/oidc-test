#!/usr/bin/env bash

set -euo pipefail

BOOTSTRAP_BUCKET="marcus-bootstrap-tfstate-798836978111"
ENABLE_VERSIONING="true"
REGION="eu-central-1"
BOOTSTRAP_DIR="terraform/bootstrap"

cleanup() {
  [[ -f "${BOOTSTRAP_DIR}/tfplan" ]] && rm -f "${BOOTSTRAP_DIR}/tfplan"
}

trap cleanup EXIT

echo "Prüfe AWS Identität..."
aws sts get-caller-identity

echo "Prüfe Bootstrap-State-Bucket..."

if aws s3api head-bucket --bucket "${BOOTSTRAP_BUCKET}" 2>/dev/null; then
  echo "Bootstrap-State-Bucket existiert bereits."
else
  echo "Erstelle Bootstrap-State-Bucket..."

  aws s3api create-bucket \
    --bucket "${BOOTSTRAP_BUCKET}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"

  echo "Aktiviere Versioning..."
  if [ "${ENABLE_VERSIONING}" = "true" ]; then
  echo "Aktiviere Versioning..."
  aws s3api put-bucket-versioning \
    --bucket "${BOOTSTRAP_BUCKET}" \
    --versioning-configuration Status=Enabled
  else
  echo "Setze Versioning auf Suspended..."
  aws s3api put-bucket-versioning \
    --bucket "${BOOTSTRAP_BUCKET}" \
    --versioning-configuration Status=Suspended
  fi

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

  echo "Bootstrap-State-Bucket wurde erstellt."
fi

echo "Initialisiere Bootstrap Terraform..."
terraform -chdir="${BOOTSTRAP_DIR}" init -reconfigure

echo "Validiere Bootstrap Terraform..."
terraform -chdir="${BOOTSTRAP_DIR}" validate

echo "Erstelle Bootstrap Plan..."
terraform -chdir="${BOOTSTRAP_DIR}" plan -out=tfplan

echo "Wende Bootstrap an..."
terraform -chdir="${BOOTSTRAP_DIR}" apply tfplan

echo
echo "Bootstrap erfolgreich abgeschlossen."
echo "GitHub OIDC Provider, IAM Role und Infrastructure-State-Bucket sollten jetzt vorhanden sein."
