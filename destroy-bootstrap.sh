#!/usr/bin/env bash

set -euo pipefail

BOOTSTRAP_BUCKET="marcus-bootstrap-tfstate-798836978111"
INFRASTRUCTURE_BUCKET="marcus-infrastructure-tfstate-798836978111"

REGION="eu-central-1"
BOOTSTRAP_DIR="terraform/bootstrap"

# --------------------------------------------------
# Temp-Dateien zentral tracken und immer aufräumen
# --------------------------------------------------

TMP_FILES=()

cleanup() {
  local f
  for f in "${TMP_FILES[@]:-}"; do
    [[ -n "${f}" && -f "${f}" ]] && rm -f "${f}"
  done
  [[ -f "${BOOTSTRAP_DIR}/destroy.tfplan" ]] && rm -f "${BOOTSTRAP_DIR}/destroy.tfplan"
}

trap cleanup EXIT

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
  local bucket="$1"
  aws s3api head-bucket --bucket "${bucket}" >/dev/null 2>&1
}

# Zählt robust, auch wenn die Query mal "None" oder leer liefert
count_items() {
  local bucket="$1"
  local field="$2" # Versions oder DeleteMarkers
  local count

  count=$(aws s3api list-object-versions \
    --bucket "${bucket}" \
    --max-items 1000 \
    --query "length(${field} || \`[]\`)" \
    --output text 2>/dev/null || echo 0)

  [[ "${count}" =~ ^[0-9]+$ ]] || count=0

  echo "${count}"
}

delete_batch() {
  local bucket="$1"
  local field="$2" # Versions oder DeleteMarkers
  local tmp_file="$3"

  aws s3api list-object-versions \
    --bucket "${bucket}" \
    --max-items 1000 \
    --query "{Objects: (${field} || \`[]\`)[].{Key:Key,VersionId:VersionId},Quiet:\`true\`}" \
    --output json \
    > "${tmp_file}"

  aws s3api delete-objects \
    --bucket "${bucket}" \
    --delete "file://${tmp_file}" \
    >/dev/null
}

delete_all_bucket_versions() {
  local bucket="$1"

  local versions_file="/tmp/${bucket}-versions.json"
  local markers_file="/tmp/${bucket}-delete-markers.json"
  TMP_FILES+=("${versions_file}" "${markers_file}")

  echo
  echo "Leere Bucket: ${bucket}"
  echo "----------------------------------------"

  echo "Lösche Objektversionen..."
  while true; do
    local version_count
    version_count=$(count_items "${bucket}" "Versions")

    if [[ "${version_count}" -eq 0 ]]; then
      break
    fi

    echo "Gefundene Objektversionen in diesem Durchlauf: ${version_count}"
    delete_batch "${bucket}" "Versions" "${versions_file}"
    echo "${version_count} Objektversionen gelöscht."
  done

  echo "Lösche Delete Marker..."
  while true; do
    local marker_count
    marker_count=$(count_items "${bucket}" "DeleteMarkers")

    if [[ "${marker_count}" -eq 0 ]]; then
      break
    fi

    echo "Gefundene Delete Marker in diesem Durchlauf: ${marker_count}"
    delete_batch "${bucket}" "DeleteMarkers" "${markers_file}"
    echo "${marker_count} Delete Marker gelöscht."
  done

  rm -f "${versions_file}" "${markers_file}"

  # --------------------------------------------------
  # Abschließende Kontrolle
  # --------------------------------------------------

  local remaining_versions remaining_markers remaining_objects

  remaining_versions=$(count_items "${bucket}" "Versions")
  remaining_markers=$(count_items "${bucket}" "DeleteMarkers")

  remaining_objects=$(aws s3api list-objects-v2 \
    --bucket "${bucket}" \
    --query 'KeyCount' \
    --output text 2>/dev/null || echo 0)
  [[ "${remaining_objects}" =~ ^[0-9]+$ ]] || remaining_objects=0

  echo
  echo "Kontrolle für ${bucket}:"
  echo "Aktuelle Objekte : ${remaining_objects}"
  echo "Versionen        : ${remaining_versions}"
  echo "Delete Marker    : ${remaining_markers}"

  if [[ "${remaining_objects}" -ne 0 ]] ||
     [[ "${remaining_versions}" -ne 0 ]] ||
     [[ "${remaining_markers}" -ne 0 ]]; then
    echo
    echo "FEHLER: Bucket ${bucket} konnte nicht vollständig geleert werden."
    exit 1
  fi

  echo
  echo "Bucket ${bucket} ist vollständig leer."
}

# Löscht einen leeren Bucket mit Retry, da S3 nach dem letzten
# delete-objects noch kurzzeitig "BucketNotEmpty" melden kann
# (eventual consistency).
delete_bucket_with_retry() {
  local bucket="$1"
  local attempt=1
  local max_attempts=5

  while (( attempt <= max_attempts )); do
    if aws s3api delete-bucket --bucket "${bucket}" --region "${REGION}" 2>/tmp/delete-bucket-err.log; then
      rm -f /tmp/delete-bucket-err.log
      return 0
    fi

    if grep -qi "BucketNotEmpty" /tmp/delete-bucket-err.log 2>/dev/null; then
      echo "Bucket noch nicht als leer erkannt (Versuch ${attempt}/${max_attempts}), warte kurz..."
      sleep $((attempt * 2))
      attempt=$((attempt + 1))
      continue
    fi

    echo "FEHLER beim Löschen von ${bucket}:"
    cat /tmp/delete-bucket-err.log 2>/dev/null || true
    rm -f /tmp/delete-bucket-err.log
    return 1
  done

  echo "FEHLER: ${bucket} konnte auch nach ${max_attempts} Versuchen nicht gelöscht werden."
  return 1
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
# Infrastructure State Bucket leeren
#
# Terraform kann den Bucket im nachfolgenden destroy nur
# löschen, wenn wirklich ALLE Versionen und Delete Marker
# vorher entfernt wurden.
# --------------------------------------------------

echo
echo "Prüfe Infrastructure-State-Bucket..."

if bucket_exists "${INFRASTRUCTURE_BUCKET}"; then
  echo "Infrastructure-State-Bucket existiert."
  echo "Leere ihn vor terraform destroy..."
  delete_all_bucket_versions "${INFRASTRUCTURE_BUCKET}"
else
  echo "Infrastructure-State-Bucket existiert nicht."
fi

# --------------------------------------------------
# Bootstrap Terraform destroy
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
#
# Erst jetzt, da Terraform seinen eigenen State bis zum
# Abschluss des destroy benötigt.
# --------------------------------------------------

echo
echo "Prüfe Bootstrap-State-Bucket..."

if bucket_exists "${BOOTSTRAP_BUCKET}"; then
  delete_all_bucket_versions "${BOOTSTRAP_BUCKET}"

  echo
  echo "Lösche Bootstrap-State-Bucket..."
  delete_bucket_with_retry "${BOOTSTRAP_BUCKET}"
  echo "Bootstrap-State-Bucket wurde gelöscht."
else
  echo "Bootstrap-State-Bucket existiert nicht."
fi

echo
echo "========================================"
echo "Bootstrap vollständig gelöscht."
echo "========================================"
