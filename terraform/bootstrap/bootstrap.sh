#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

REGION="eu-central-1"
ENABLE_VERSIONING="true"

# Environments, die gebootstrappt werden, und das jeweilige lokale
# AWS-Profil. Neue Umgebung hinzufügen/entfernen/umbenennen: Eintrag hier
# ergänzen/anpassen und passende envs/<env>.backend.hcl anlegen.
ENVIRONMENTS=(dev test prod)
declare -A AWS_PROFILES=(
  [dev]="hsr_dev"
  [test]="hsr_test"
  [prod]="hsr_prod"
)

cleanup() {
  [[ -f "tfplan" ]] && rm -f "tfplan"
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

bootstrap_environment() {
  local env="$1"
  local profile="${AWS_PROFILES[${env}]}"
  local bootstrap_bucket="bootstrap_state_${env}"

  echo
  echo "========================================"
  echo "Bootstrap: ${env} (AWS-Profil: ${profile})"
  echo "========================================"

  export AWS_PROFILE="${profile}"
  export TF_VAR_environment="${env}"

  echo "Prüfe AWS Identität..."
  aws sts get-caller-identity

  echo "Prüfe Bootstrap-State-Bucket..."

  if aws s3api head-bucket --bucket "${bootstrap_bucket}" 2>/dev/null; then
    echo "Bootstrap-State-Bucket existiert bereits."
  else
    echo "Erstelle Bootstrap-State-Bucket..."

    aws s3api create-bucket \
      --bucket "${bootstrap_bucket}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"

    if [ "${ENABLE_VERSIONING}" = "true" ]; then
      echo "Aktiviere Versioning..."
      aws s3api put-bucket-versioning \
        --bucket "${bootstrap_bucket}" \
        --versioning-configuration Status=Enabled
    else
      echo "Setze Versioning auf Suspended..."
      aws s3api put-bucket-versioning \
        --bucket "${bootstrap_bucket}" \
        --versioning-configuration Status=Suspended
    fi

    echo "Aktiviere SSE-S3 Verschlüsselung..."
    aws s3api put-bucket-encryption \
      --bucket "${bootstrap_bucket}" \
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
      --bucket "${bootstrap_bucket}" \
      --public-access-block-configuration \
'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

    echo "Bootstrap-State-Bucket wurde erstellt."
  fi

  echo "Initialisiere Bootstrap Terraform..."
  terraform init -backend-config="envs/${env}.backend.hcl" -reconfigure

  echo "Validiere Bootstrap Terraform..."
  terraform validate

  echo "Erstelle Bootstrap Plan..."
  terraform plan -out=tfplan

  echo "Wende Bootstrap an..."
  terraform apply tfplan

  rm -f tfplan

  echo
  echo "Bootstrap für ${env} abgeschlossen."
}

echo "Prüfe benötigte Tools..."
require_command aws
require_command terraform
require_command gh

detect_github_oidc_vars

for env in "${ENVIRONMENTS[@]}"; do
  bootstrap_environment "${env}"
done

echo
echo "========================================"
echo "Bootstrap für alle Umgebungen (${ENVIRONMENTS[*]}) erfolgreich abgeschlossen."
echo "GitHub OIDC Provider, IAM Role und Infrastructure-State-Bucket sollten"
echo "jetzt in jedem der zugehörigen AWS-Accounts vorhanden sein."
echo "========================================"
