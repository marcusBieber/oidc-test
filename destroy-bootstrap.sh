#!/usr/bin/env bash

set -euo pipefail

BOOTSTRAP_BUCKET="marcus-bootstrap-tfstate-798836978111"
REGION="eu-central-1"
BOOTSTRAP_DIR="terraform/bootstrap"

# --------------------------------------------------
# Hilfsfunktionen
# --------------------------------------------------

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "FEHLER: '$1' ist nicht installiert oder nicht im PATH."
    exit 1
  fi
}

bucket_exists() {
  aws s3api head-bucket \
    --bucket "${BOOTSTRAP_BUCKET}" \
    >/dev/null 2>&1
}

delete_all_bucket_versions() {
  echo "Lösche alle Objektversionen und Delete Marker..."

  while true; do

    VERSION_COUNT=$(aws s3api list-object-versions \
      --bucket "${BOOTSTRAP_BUCKET}" \
      --query 'length(Versions)' \
      --output text)

    if [[ "${VERSION_COUNT}" != "None" && "${VERSION_COUNT}" -gt 0 ]]; then

      aws s3api list-object-versions \
        --bucket "${BOOTSTRAP_BUCKET}" \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId},Quiet:`true`}' \
        --output json \
        > /tmp/bootstrap-versions.json

      aws s3api delete-objects \
        --bucket "${BOOTSTRAP_BUCKET}" \
        --delete file:///tmp/bootstrap-versions.json \
        >/dev/null
    fi

    MARKER_COUNT=$(aws s3api list-object-versions \
      --bucket "${BOOTSTRAP_BUCKET}" \
      --query 'length(DeleteMarkers)' \
      --output text)

    if [[ "${MARKER_COUNT}" != "None" && "${MARKER_COUNT}" -gt 0 ]]; then

      aws s3api list-object-versions \
        --bucket "${BOOTSTRAP_BUCKET}" \
        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId},Quiet:`true`}' \
        --output json \
        > /tmp/bootstrap-delete-markers.json

      aws s3api delete-objects \
        --bucket "${BOOTSTRAP_BUCKET}" \
        --delete file:///tmp/bootstrap-delete-markers.json \
        >/dev/null
    fi

    if [[ "${VERSION_COUNT}" == "None" || "${VERSION_COUNT}" -eq 0 ]] &&
       [[ "${MARKER_COUNT}" == "None" || "${MARKER_COUNT}" -eq 0 ]]; then
      break
    fi
  done

  rm -f /tmp/bootstrap-versions.json
  rm -f /tmp/bootstrap-delete-markers.json

  echo "Bucket ist leer."
}

# --------------------------------------------------
# Voraussetzungen prüfen
# --------------------------------------------------

echo "Prüfe benötigte Tools..."

require_command aws
require_command terraform

echo "AWS CLI und Terraform vorhanden."

# --------------------------------------------------
# AWS Identität
# --------------------------------------------------

echo
echo "Aktuelle AWS Identität:"

aws sts get-caller-identity

echo
echo "WARNUNG"
echo "Dieses Skript zerstört:"
echo "- GitHub OIDC Provider"
echo "- IAM Role und zugehörige Bootstrap-Ressourcen"
echo "- Infrastructure-State-Bucket"
echo "- Bootstrap-State-Bucket inklusive aller Versionen"
echo
echo "Die eigentliche Infrastructure sollte vorher bereits zerstört worden sein."
echo

read -r -p "Bootstrap wirklich vollständig löschen? (yes/no): " CONFIRM

if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Abgebrochen."
  exit 0
fi

# --------------------------------------------------
# Bootstrap Terraform zerstören
# --------------------------------------------------

echo
echo "Initialisiere Bootstrap Terraform..."

terraform -chdir="${BOOTSTRAP_DIR}" init -reconfigure

echo
echo "Erstelle Destroy Plan..."

terraform -chdir="${BOOTSTRAP_DIR}" plan \
  -destroy \
  -out=destroy.tfplan

echo
echo "Zerstöre Bootstrap Ressourcen..."

terraform -chdir="${BOOTSTRAP_DIR}" apply \
  destroy.tfplan

echo
echo "Terraform Bootstrap wurde zerstört."

# --------------------------------------------------
# Bootstrap State Bucket löschen
# --------------------------------------------------

echo
echo "Prüfe Bootstrap-State-Bucket..."

if bucket_exists; then

  delete_all_bucket_versions

  echo
  echo "Lösche Bootstrap-State-Bucket..."

  aws s3api delete-bucket \
    --bucket "${BOOTSTRAP_BUCKET}" \
    --region "${REGION}"

  echo "Bootstrap-State-Bucket wurde gelöscht."

else
  echo "Bootstrap-State-Bucket existiert nicht."
fi

echo
echo "Bootstrap vollständig gelöscht."
