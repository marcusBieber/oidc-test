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
