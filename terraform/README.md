# terraform/

Hier läuft die **eigentliche Test-Infrastruktur** – das ist der Teil, der
über die per Bootstrap angelegte OIDC-Rolle (`github-oidc-test`) aus GitHub
Actions heraus provisioniert wird (Workflow `terraform-s3.yml`).

Aktuell wird hier nur ein einzelner S3-Bucket
(`aws_s3_bucket.oidc_test`, `main.tf`) erstellt – bewusst minimal gehalten,
da der Zweck dieses Verzeichnisses ist, die OIDC-Verbindungskette
end-to-end zu belegen (Rolle übernehmen → Terraform → AWS-Ressource
anlegen), nicht produktive Infrastruktur abzubilden.

- `main.tf` – Provider-Konfiguration und die Test-Ressource(n).
- `backend.tf` – S3-Backend für den Terraform-State dieses Verzeichnisses;
  zeigt auf den Infrastructure-State-Bucket, der im Bootstrap-Schritt
  (`terraform/bootstrap/`) angelegt wird. Ohne erfolgreichen Bootstrap
  existiert dieser Bucket nicht und `terraform init` schlägt fehl.

Ausführung erfolgt normalerweise automatisiert über
`.github/workflows/terraform-s3.yml`; für lokale/manuelle Läufe genügt:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform plan
terraform -chdir=terraform apply
```

Details zum Gesamtaufbau und zum Bootstrap-Schritt stehen im
[Haupt-README](../README.md) bzw. in
[`bootstrap/README.md`](bootstrap/README.md).
