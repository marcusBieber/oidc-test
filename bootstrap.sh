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

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "FEHLER: '$1' ist nicht installiert oder nicht im PATH."
    exit 1
  fi
}

detect_github_oidc_vars() {
  echo "Ermittle GitHub-Repository-Informationen (gh.com vs. GHES)..."

  require_command gh

  local repo_nwo repo_host repo_id owner_id

  repo_nwo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
  repo_host=$(gh repo view --json url --jq '.url' | awk -F/ '{print $3}')

  export TF_VAR_github_owner="${repo_nwo%%/*}"
  export TF_VAR_github_repo="${repo_nwo##*/}"

  repo_id=$(gh api "repos/${repo_nwo}" --jq '.id')

  if [[ "${repo_host}" == "github.com" ]]; then
    owner_id=$(gh api "repos/${repo_nwo}" --jq '.owner.id')

    echo "github.com erkannt (Owner-ID=${owner_id}, Repo-ID=${repo_id})."

    export TF_VAR_github_owner_id="${owner_id}"
    export TF_VAR_github_repo_id="${repo_id}"
    unset TF_VAR_github_repo_id_ghes
    export TF_VAR_github_oidc_provider_url="https://token.actions.githubusercontent.com"
  else
    echo "GitHub Enterprise Server erkannt (Host=${repo_host}, Repo-ID=${repo_id})."
    echo "Hinweis: Pfad des OIDC-Token-Endpunkts ggf. an eure GHES-Konfiguration anpassen."

    unset TF_VAR_github_owner_id
    unset TF_VAR_github_repo_id
    export TF_VAR_github_repo_id_ghes="${repo_id}"
    export TF_VAR_github_oidc_provider_url="https://${repo_host}/_services/token"
  fi
}

echo "Prüfe AWS Identität..."
aws sts get-caller-identity

detect_github_oidc_vars

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
