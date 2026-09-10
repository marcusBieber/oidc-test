#!/usr/bin/env bash

set -euo pipefail

BOOTSTRAP_BUCKET="marcus-bootstrap-tfstate-798836978111"
REGION="eu-central-1"
BOOTSTRAP_DIR="terraform/bootstrap"

install_jq_if_missing() {
  if command -v jq >/dev/null 2>&1; then
    echo "jq ist bereits installiert."
    return
  fi

  echo "jq wurde nicht gefunden. Installation wird versucht..."

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y jq
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y jq
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y jq
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm jq
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper --non-interactive install jq
  else
    echo "Kein unterstützter Paketmanager gefunden."
    echo "Bitte jq manuell installieren und das Skript erneut starten."
    exit 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "jq konnte nicht erfolgreich installiert werden."
    exit 1
  fi

  echo "jq wurde erfolgreich installiert."
}

echo "Prüfe benötigte Tools..."
install_jq_if_missing

echo
echo "Prüfe AWS Identität..."
aws sts get-caller-identity

echo
echo "WARNUNG:"
echo "Dieses Skript zerstört die Bootstrap-Ressourcen und löscht den Bootstrap-State-Bucket."
echo "Die normale Infrastructure sollte vorher bereits mit Terraform zerstört worden sein."
echo

read -r -p "Bootstrap wirklich löschen? (yes/no): " CONFIRM

if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Abgebrochen."
  exit 0
fi

echo
echo "Initialisiere Bootstrap Terraform..."
terraform -chdir="${BOOTSTRAP_DIR}" init -reconfigure

echo
echo "Erstelle Destroy-Plan..."
terraform -chdir="${BOOTSTRAP_DIR}" plan -destroy -out=destroy.tfplan

echo
echo "Zerstöre Bootstrap-Ressourcen..."
terraform -chdir="${BOOTSTRAP_DIR}" apply destroy.tfplan

echo
echo "Bootstrap-Ressourcen wurden zerstört."

echo
echo "Prüfe Bootstrap-State-Bucket..."

if ! aws s3api head-bucket \
  --bucket "${BOOTSTRAP_BUCKET}" 2>/dev/null; then

  echo "Bootstrap-State-Bucket existiert nicht mehr."
  exit 0
fi

echo
echo "Lösche alle Objektversionen..."

aws s3api list-object-versions \
  --bucket "${BOOTSTRAP_BUCKET}" \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
  --output json \
  > /tmp/bootstrap-versions.json

VERSION_COUNT=$(jq '.Objects | length' /tmp/bootstrap-versions.json)

if [[ "${VERSION_COUNT}" -gt 0 ]]; then
  aws s3api delete-objects \
    --bucket "${BOOTSTRAP_BUCKET}" \
    --delete file:///tmp/bootstrap-versions.json
else
  echo "Keine Objektversionen vorhanden."
fi

echo
echo "Lösche alle Delete Marker..."

aws s3api list-object-versions \
  --bucket "${BOOTSTRAP_BUCKET}" \
  --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
  --output json \
  > /tmp/bootstrap-delete-markers.json

MARKER_COUNT=$(jq '.Objects | length' /tmp/bootstrap-delete-markers.json)

if [[ "${MARKER_COUNT}" -gt 0 ]]; then
  aws s3api delete-objects \
    --bucket "${BOOTSTRAP_BUCKET}" \
    --delete file:///tmp/bootstrap-delete-markers.json
else
  echo "Keine Delete Marker vorhanden."
fi

echo
echo "Lösche Bootstrap-State-Bucket..."

aws s3api delete-bucket \
  --bucket "${BOOTSTRAP_BUCKET}" \
  --region "${REGION}"

rm -f /tmp/bootstrap-versions.json
rm -f /tmp/bootstrap-delete-markers.json

echo
echo "Bootstrap vollständig gelöscht."
