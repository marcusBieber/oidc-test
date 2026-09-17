# terraform/

Hier läuft die **eigentliche Test-Infrastruktur** – das ist der Teil, der
über die per Bootstrap angelegten OIDC-Rollen aus GitHub Actions heraus
provisioniert wird (Workflow `terraform-s3.yml`).

Je AWS-Account/Environment gibt es ein eigenes Unterverzeichnis:

- `hsr-dev/`, `hsr-test/`, `hsr-prod/` – identischer Inhalt, nur der
  Backend-Bucket in `backend.tf` unterscheidet sich (`infra_state_dev`,
  `infra_state_test`, `infra_state_prod`).
- `bootstrap/` – das Bootstrap-Modul, siehe
  [`bootstrap/README.md`](bootstrap/README.md).

Aktuell wird pro Environment nur ein einzelner S3-Bucket
(`aws_s3_bucket.oidc_test`, `main.tf`) erstellt – bewusst minimal gehalten,
da der Zweck dieser Verzeichnisse ist, die OIDC-Verbindungskette
end-to-end zu belegen (Rolle übernehmen → Terraform → AWS-Ressource
anlegen), nicht produktive Infrastruktur abzubilden.

- `main.tf` – Provider-Konfiguration und die Test-Ressource(n), in jedem
  `hsr-*`-Verzeichnis identisch.
- `backend.tf` – S3-Backend für den Terraform-State des jeweiligen
  Environments; zeigt auf den Infrastructure-State-Bucket, der im
  Bootstrap-Schritt (`terraform/bootstrap/`) für dieses Environment angelegt
  wird. Ohne erfolgreichen Bootstrap existiert dieser Bucket nicht und
  `terraform init` schlägt fehl.

Ausführung erfolgt normalerweise automatisiert über
`.github/workflows/terraform-s3.yml` (Matrix über alle drei Environments);
für lokale/manuelle Läufe genügt pro Environment:

```bash
terraform -chdir=terraform/hsr-dev init
terraform -chdir=terraform/hsr-dev plan
terraform -chdir=terraform/hsr-dev apply
```

(entsprechend für `hsr-test`/`hsr-prod`).

Details zum Gesamtaufbau und zum Bootstrap-Schritt stehen im
[Haupt-README](../README.md) bzw. in
[`bootstrap/README.md`](bootstrap/README.md).
