# "bucket" wird nicht hier gesetzt, sondern von bootstrap.sh/destroy-bootstrap.sh
# zur Laufzeit per zusätzlichem -backend-config="bucket=bootstrap-state-prod-<account-id>"
# ergänzt, da S3-Bucket-Namen global eindeutig sein müssen.
key          = "bootstrap/terraform.tfstate"
region       = "eu-central-1"
encrypt      = true
use_lockfile = true
