# oidc-test

Terraform-Setup für eine **keyless AWS-Anbindung von GitHub Actions per
OpenID Connect (OIDC)** über mehrere AWS-Accounts/Environments (dev, test,
prod) hinweg. Statt langlebiger AWS Access Keys als GitHub Secret nutzt die
CI-Pipeline ein kurzlebiges, von GitHub signiertes Token, das AWS je
Environment gegen eine eigene IAM-Rolle eintauscht
(`sts:AssumeRoleWithWebIdentity`).

Das Repo ist zweigeteilt:

- **[`terraform/bootstrap/`](terraform/bootstrap/README.md)** – das
  wiederverwendbare Bootstrap-Modul: legt pro Environment einmalig OIDC-
  Provider, IAM-Rolle und State-Buckets an. Enthält die vollständige
  Dokumentation (Zweck, Aufbau, Nutzung, Voraussetzungen).
- **[`terraform/`](terraform/README.md)** – die eigentlichen, über die
  gebootstrappten Rollen per GitHub Actions provisionierten Workloads
  (`hsr-dev/`, `hsr-test/`, `hsr-prod/`).

Details stehen in den jeweiligen READMEs der beiden Verzeichnisse.

## Voraussetzungen

AWS CLI, Terraform (`>= 1.5.0`) und GitHub CLI (`gh`, authentifiziert).
Vollständige Liste inkl. Berechtigungen: siehe
[`terraform/bootstrap/README.md`](terraform/bootstrap/README.md#voraussetzungen).

## Erste Schritte

1. [`terraform/bootstrap/README.md`](terraform/bootstrap/README.md) lesen
   und die dort verlinkte **Platzhalter-Checkliste** abarbeiten (lokale
   AWS-Profile eintragen, optional `terraform.tfvars`).
2. `terraform/bootstrap/bootstrap.sh` ausführen – legt OIDC-Provider,
   IAM-Rolle und State-Buckets in allen Environments an.
3. Nach dem Bootstrap: Account-IDs aus der Skript-Ausgabe in
   `terraform/hsr-*/backend.tf` und in den beiden Workflow-Dateien
   (`.github/workflows/*.yml`) eintragen (Platzhalter `<AWS_ACCOUNT_ID_...>`).
4. Workflow **„Test AWS OIDC“** manuell auslösen, um die OIDC-Verbindung
   zu verifizieren.
5. Workflow **„Terraform S3 Test“** manuell auslösen, um die Workload-
   Infrastruktur (`terraform/hsr-*`) über die gebootstrappte Rolle zu
   provisionieren.

## GitHub Actions Workflows

Beide sind manuell auslösbar (`workflow_dispatch`) und benötigen
`permissions: id-token: write`:

- **`test-oidc.yml`** – übernimmt die Rolle `github-oidc-test` und ruft
  `aws sts get-caller-identity` auf. Reiner Verbindungstest ohne Terraform.
- **`terraform-s3.yml`** – führt Terraform in `terraform/hsr-dev`,
  `hsr-test` und `hsr-prod` aus und deployed ein Testressource
  (Matrix über alle drei Environments).
