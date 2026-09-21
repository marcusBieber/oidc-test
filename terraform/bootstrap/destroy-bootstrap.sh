#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

REGION="eu-central-1"

# Muss zu bootstrap.sh passen (gleiche Environments/Profile).
ENVIRONMENTS=(dev test prod)
declare -A AWS_PROFILES=(
  [dev]="hsr-1-dev"
  [test]="hsr-1-tst"
  [prod]="hsr-1-prd"
)

# --------------------------------------------------
# Temp-Dateien zentral tracken und immer aufräumen
# --------------------------------------------------

TMP_FILES=()

cleanup() {
  local f
  for f in "${TMP_FILES[@]:-}"; do
    [[ -n "${f}" && -f "${f}" ]] && rm -f "${f}"
  done
  [[ -f "destroy.tfplan" ]] && rm -f "destroy.tfplan"
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
# Destroy für eine einzelne Umgebung
# --------------------------------------------------

destroy_environment() {
  local env="$1"
  local profile="${AWS_PROFILES[${env}]}"
  local infrastructure_bucket="infra-state-${env}"
  local bootstrap_bucket="bootstrap-state-${env}"

  echo
  echo "========================================"
  echo "Destroy: ${env} (AWS-Profil: ${profile})"
  echo "========================================"

  export AWS_PROFILE="${profile}"
  export TF_VAR_environment="${env}"

  echo "Aktuelle AWS Identität:"
  aws sts get-caller-identity

  echo
  echo "Prüfe Infrastructure-State-Bucket..."

  if bucket_exists "${infrastructure_bucket}"; then
    echo "Infrastructure-State-Bucket existiert."
    echo "Leere ihn vor terraform destroy..."
    delete_all_bucket_versions "${infrastructure_bucket}"
  else
    echo "Infrastructure-State-Bucket existiert nicht."
  fi

  echo
  echo "Initialisiere Bootstrap Terraform..."
  terraform init -backend-config="envs/${env}.backend.hcl" -reconfigure

  echo
  echo "Erstelle Destroy Plan..."
  terraform plan \
    -destroy \
    -out=destroy.tfplan

  echo
  echo "Zerstöre Bootstrap Ressourcen..."
  terraform apply \
    destroy.tfplan

  rm -f destroy.tfplan

  echo
  echo "Terraform Bootstrap für ${env} wurde zerstört."

  echo
  echo "Prüfe Bootstrap-State-Bucket..."

  if bucket_exists "${bootstrap_bucket}"; then
    delete_all_bucket_versions "${bootstrap_bucket}"

    echo
    echo "Lösche Bootstrap-State-Bucket..."
    delete_bucket_with_retry "${bootstrap_bucket}"
    echo "Bootstrap-State-Bucket wurde gelöscht."
  else
    echo "Bootstrap-State-Bucket existiert nicht."
  fi
}

# --------------------------------------------------
# Voraussetzungen prüfen
# --------------------------------------------------

echo "Prüfe benötigte Tools..."
require_command aws
require_command terraform
echo "AWS CLI und Terraform vorhanden."

echo
echo "WARNUNG"
echo "Dieses Skript zerstört für JEDE der folgenden Umgebungen (${ENVIRONMENTS[*]}):"
echo "- GitHub OIDC Provider"
echo "- IAM Role und zugehörige Bootstrap-Ressourcen"
echo "- Infrastructure-State-Bucket"
echo "- Bootstrap-State-Bucket inklusive aller Versionen"
echo
echo "Betroffene AWS-Profile: ${AWS_PROFILES[dev]}, ${AWS_PROFILES[test]}, ${AWS_PROFILES[prod]}"
echo
echo "Die eigentliche Infrastructure (terraform/hsr-*) sollte vorher bereits"
echo "separat zerstört worden sein."
echo

read -r -p "Bootstrap in ALLEN Umgebungen wirklich vollständig löschen? (yes/no): " CONFIRM

if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Abgebrochen."
  exit 0
fi

for env in "${ENVIRONMENTS[@]}"; do
  destroy_environment "${env}"
done

echo
echo "========================================"
echo "Bootstrap in allen Umgebungen (${ENVIRONMENTS[*]}) vollständig gelöscht."
echo "========================================"
