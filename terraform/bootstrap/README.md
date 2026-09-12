# terraform/bootstrap/

Legt die **einmalige Grundlage** für die OIDC-Anbindung an – die Ressourcen
hier müssen existieren, bevor GitHub Actions überhaupt eine AWS-Rolle
übernehmen oder Terraform-State in S3 ablegen kann. Wird ausschließlich
lokal ausgeführt (über `../../bootstrap.sh` bzw. `../../destroy-bootstrap.sh`
im Repo-Root), nicht über GitHub Actions – die dafür nötige IAM-Rolle
entsteht ja erst durch diesen Schritt selbst.

## Was hier angelegt wird (`main.tf`)

- `aws_iam_openid_connect_provider.github` – der OIDC-Identitätsanbieter,
  über dessen URL (`var.github_oidc_provider_url`) GitHub Actions Tokens für
  AWS verifizierbar signiert.
- `aws_iam_role.github_oidc_test` – die Rolle, die GitHub Actions per
  `AssumeRoleWithWebIdentity` übernimmt. Die Trust-Policy schränkt das per
  Conditions auf ein bestimmtes Repo und einen bestimmten Branch ein
  (`var.github_owner`/`github_repo`/`github_branch`).
- `aws_iam_role_policy_attachment.s3_full_access` – hängt
  `AmazonS3FullAccess` an die Rolle (bewusst grob gehalten, da Testprojekt).
- `aws_s3_bucket.infrastructure_state` (+ Versioning, SSE-Verschlüsselung,
  Public-Access-Block) – der State-Bucket für die eigentliche
  Test-Infrastruktur in `../` (`terraform/`).

Der State dieses Bootstrap-Schritts selbst liegt in einem separaten Bucket
(`backend.tf`, `marcus-bootstrap-tfstate-...`) – getrennt vom
Infrastructure-State-Bucket, damit ein `destroy` der Test-Infrastruktur den
Bootstrap-State nicht gefährdet.

## GitHub.com vs. GitHub Enterprise Server (GHES)

Um das Risiko von Namens-Recycling abzudecken (ein gelöschtes/umbenanntes
Repo, dessen Name später von jemand anderem neu vergeben wird und damit
theoretisch in den Genuss der Trust-Policy käme), gibt es je nach
Plattform einen anderen Absicherungsmechanismus:

- **GitHub.com** unterstützt „Immutable Subject Claims“: Owner- und Repo-ID
  werden fest in den `sub`-Claim des Tokens eingebettet
  (`repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:...`). Dafür:
  `github_owner_id` und `github_repo_id` setzen.
- **GHES** unterstützt das (je nach Version) nicht in dieser Form, liefert
  aber die Repo-ID als eigenen Claim `repository_id`. Dafür:
  `github_owner_id`/`github_repo_id` auf `null` lassen und stattdessen
  `github_repo_id_ghes` setzen – erzeugt eine zusätzliche eigenständige
  Trust-Policy-Condition auf diesen Claim.

Zusätzlich muss die OIDC-Provider-URL (`github_oidc_provider_url`) auf den
jeweiligen Token-Endpunkt zeigen:
- gh.com: `https://token.actions.githubusercontent.com` (Default)
- GHES: `https://<ghes-host>/_services/token` (Pfad je nach
  GHES-Konfiguration prüfen)

**Wichtig:** AWS benennt die Condition-Keys im Trust-Dokument
(`...:aud`, `...:sub`, `...:repository_id`) nach dem Host der registrierten
Provider-URL. Ändert sich `github_oidc_provider_url`, wandert der
Condition-Namespace in `main.tf` automatisch mit (`local.oidc_condition_namespace`) –
das muss nicht manuell angepasst werden.

### Automatische Ermittlung

`../../bootstrap.sh` erkennt vor dem Terraform-Lauf automatisch per
GitHub CLI (`gh repo view`, `gh api`), ob gegen GitHub.com oder GHES
gearbeitet wird, und exportiert die passenden Werte als
`TF_VAR_github_*`-Umgebungsvariablen. Terraform liest diese automatisch ein
– im Regelfall muss also keine der folgenden Dateien angefasst werden.

### Manuelle Konfiguration (Fallback)

Falls `gh` nicht verfügbar ist oder abweichende Werte gebraucht werden:
`terraform.tfvars.example` nach `terraform.tfvars` kopieren (wird von
`.gitignore` ignoriert, landet also nicht im Repo) und die Werte für das
jeweilige Szenario (gh.com oder GHES) eintragen.

## Variablen (`variables.tf`)

| Variable | Zweck |
|---|---|
| `enable_versioning` | Versioning für den Infrastructure-State-Bucket an/aus |
| `github_owner` | GitHub-Benutzer- oder Organisationsname |
| `github_repo` | GitHub-Repository-Name |
| `github_branch` | Branch, für den die Rolle per Trust-Policy erlaubt ist |
| `github_owner_id` | Immutable Owner-ID (nur gh.com) |
| `github_repo_id` | Immutable Repo-ID (nur gh.com) |
| `github_repo_id_ghes` | Repo-ID als separate Condition (GHES) |
| `github_oidc_provider_url` | OIDC-Token-Endpunkt (gh.com oder GHES) |

## Ausführung

Nicht direkt `terraform` in diesem Verzeichnis aufrufen, sondern über die
Skripte im Repo-Root, da diese zusätzlich den Bootstrap-State-Bucket
anlegen/leeren und (bei `bootstrap.sh`) die GitHub-Variablen automatisch
ermitteln:

```bash
../../bootstrap.sh          # anlegen
../../destroy-bootstrap.sh  # abbauen
```
