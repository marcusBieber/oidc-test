# terraform/bootstrap/

Wiederverwendbares Terraform-Modul, das die **einmalige Grundlage** für eine
keyless AWS-Anbindung von GitHub Actions per OIDC anlegt – pro
AWS-Account/Environment. Die hier erzeugten Ressourcen müssen existieren,
bevor GitHub Actions überhaupt eine AWS-Rolle übernehmen oder
Terraform-State in S3 ablegen kann. Wird ausschließlich lokal ausgeführt
(über `bootstrap.sh` bzw. `destroy-bootstrap.sh` in diesem Verzeichnis),
nicht über GitHub Actions – die dafür nötige IAM-Rolle entsteht ja erst
durch diesen Schritt selbst.

## Zweck

Dieses Repo verbindet ein einzelnes GitHub-Repository mit **mehreren
AWS-Accounts**, je einer pro Environment (`dev`, `test`, `prod`). Jeder
Account bekommt dieselbe Bootstrap-Konfiguration, aber mit eigenem
OIDC-Provider, eigener IAM-Rolle und eigenen State-Buckets – vollständig
isoliert voneinander (kein gemeinsamer State, kein gemeinsamer Account).

## Platzhalter, die vor der Nutzung ausgefüllt werden müssen

Dieses Repo ist als Vorlage gedacht und enthält daher keine echten Namen/IDs.
Checkliste, was wann auszufüllen ist:

| Reihenfolge | Datei(en) | Platzhalter | Wann bekannt |
|---|---|---|---|
| 1 | `bootstrap.sh`, `destroy-bootstrap.sh` (`AWS_PROFILES`) | `<aws-profile-dev>` / `-test` / `-prod` | Vorher – eure lokalen AWS-Profilnamen (`~/.aws/config`) |
| 2 (optional) | `terraform.tfvars` (aus `terraform.tfvars.example` kopiert) | `<github-owner>`, `<github-repo>`, `<owner-id>`, `<repo-id>` | Vorher – nur nötig, falls `gh` nicht verfügbar ist, siehe [Automatische Ermittlung](#automatische-ermittlung) |
| 3 | `../hsr-dev/backend.tf`, `../hsr-test/backend.tf`, `../hsr-prod/backend.tf` | `<AWS_ACCOUNT_ID_DEV>` / `_TEST` / `_PROD` | **Nach** dem jeweiligen Bootstrap-Lauf – die Account-ID steht in der `aws sts get-caller-identity`-Ausgabe des Laufs |
| 4 | `../../.github/workflows/terraform-s3.yml`, `../../.github/workflows/test-oidc.yml` | dieselben Account-ID-Platzhalter (als Teil der Rollen-ARN) | Nach dem Bootstrap, sobald die IAM-Rolle im jeweiligen Account existiert |

Schritt 1 ist zwingend vor dem ersten `bootstrap.sh`-Lauf nötig, Schritt 3+4
erst danach (die Accounts/Rollen müssen ja erst existieren).

## Aufbau / Funktionsweise

Das Verzeichnis wird **einmal pro Environment** mit `terraform init/plan/apply`
durchlaufen, jeweils mit einem anderen AWS-Profil und einer anderen
Backend-Konfiguration:

```
terraform/bootstrap/
├── main.tf, variables.tf, backend.tf, outputs.tf, terraform.tfvars.example
├── envs/
│   ├── dev.backend.hcl    # Backend-Config für den dev-Bootstrap-State
│   ├── test.backend.hcl
│   └── prod.backend.hcl
├── bootstrap.sh           # Legt alle Environments (Schleife) an
└── destroy-bootstrap.sh   # Reißt alle Environments (Schleife) wieder ab
```

`backend.tf` ist bewusst eine **partial configuration** (`backend "s3" {}`
ohne Werte) – die konkreten Backend-Werte (Bucket, Key, Region, ...) kommen
pro Environment aus `envs/<environment>.backend.hcl` und werden beim
`terraform init` per `-backend-config=` übergeben. So läuft dasselbe
Terraform-Verzeichnis nacheinander gegen drei getrennte States, ohne
Code-Duplizierung.

`bootstrap.sh` und `destroy-bootstrap.sh` iterieren dafür über ein
`ENVIRONMENTS`-Array und eine `AWS_PROFILES`-Map (siehe [Environments und
AWS-Profile](#environments-und-aws-profile) unten) und führen für jedes
Environment den kompletten Bootstrap- bzw. Destroy-Ablauf mit dem
passenden Profil und der passenden Backend-Config durch.

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
  Workload-Infrastruktur des jeweiligen Environments (`../hsr-<env>/`),
  benannt `infra-state-<environment>-<account-id>`.

Der State dieses Bootstrap-Schritts selbst liegt in einem separaten Bucket
je Environment (`bootstrap-state-<environment>-<account-id>`, siehe
`envs/*.backend.hcl`) – getrennt vom Infrastructure-State-Bucket, damit ein
`destroy` der Workload-Infrastruktur den Bootstrap-State nicht gefährdet.

### Bucket-Namen und die Account-ID

S3-Bucket-Namen sind **global über alle AWS-Accounts aller Kunden**
eindeutig, nicht nur innerhalb eurer drei Accounts. Ein Name wie
`bootstrap-state-dev` ist generisch genug, dass er anderswo auf der Welt
schon vergeben sein kann (`BucketAlreadyExists`). Deshalb hängen beide
State-Bucket-Namen die AWS-Account-ID an:

- `bootstrap-state-<environment>-<account-id>` – wird von `bootstrap.sh`/
  `destroy-bootstrap.sh` zur Laufzeit ermittelt (`aws sts get-caller-identity`)
  und beim `terraform init` per zusätzlichem `-backend-config="bucket=..."`
  über den Wert aus `envs/<environment>.backend.hcl` gelegt (die Datei
  selbst enthält bewusst keine `bucket`-Zeile mehr).
- `infra-state-<environment>-<account-id>` – wird direkt in `main.tf` über
  `data "aws_caller_identity" "current"` gebildet, Terraform kennt seine
  eigene Account-ID also selbst.

Da AWS-Account-IDs global eindeutig sind, ist dieses Namensschema
garantiert kollisionsfrei – ganz ohne Zufalls-Suffix.

**Wichtig:** `../hsr-dev/backend.tf`, `../hsr-test/backend.tf` und
`../hsr-prod/backend.tf` referenzieren den `infra-state`-Bucket aber
statisch (ein Verzeichnis = ein fester Account), Terraform kann dort keine
Account-ID zur Laufzeit einsetzen. Nach dem ersten erfolgreichen Bootstrap
je Environment müsst ihr dort einmalig die Platzhalter
`<AWS_ACCOUNT_ID_DEV>`/`<AWS_ACCOUNT_ID_TEST>`/`<AWS_ACCOUNT_ID_PROD>` durch
die jeweils echte Account-ID ersetzen (steht in der `aws sts
get-caller-identity`-Ausgabe des Bootstrap-Laufs).

## Environments und AWS-Profile

Welche Environments gebootstrappt werden und über welches lokale
AWS-Profil, ist in `bootstrap.sh` und `destroy-bootstrap.sh` als Variable
hinterlegt:

```bash
ENVIRONMENTS=(dev test prod)
declare -A AWS_PROFILES=(
  [dev]="<aws-profile-dev>"
  [test]="<aws-profile-test>"
  [prod]="<aws-profile-prod>"
)
```

**Vor der ersten Nutzung ausfüllen:** die drei Platzhalter durch eure
tatsächlichen lokalen AWS-Profilnamen ersetzen (siehe
[Voraussetzungen](#voraussetzungen)).

Die Profile müssen lokal in `~/.aws/config`/`~/.aws/credentials` existieren
und Berechtigung haben, einen IAM OIDC Provider, eine IAM-Rolle samt
Policy-Attachment und S3-Buckets im jeweiligen Account anzulegen.

**Ein Environment hinzufügen, entfernen oder umbenennen:**
1. Eintrag in `ENVIRONMENTS` und `AWS_PROFILES` in **beiden** Skripten
   ergänzen/anpassen.
2. Passende `envs/<environment>.backend.hcl` anlegen (ohne `bucket`-Zeile,
   siehe vorhandene Dateien als Vorlage – der Bucket-Name
   `bootstrap-state-<environment>-<account-id>` wird von den Skripten zur
   Laufzeit ergänzt).
3. `variables.tf` → `environment`-Validierung (`contains(["dev", "test",
   "prod"], ...)`) um den neuen Namen erweitern.
4. Passendes `../hsr-<environment>/` Workload-Verzeichnis anlegen (siehe
   [`../README.md`](../README.md)).

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
Condition-Namespace in `main.tf` automatisch mit (`local.oidc_condition_namespace`)
– das muss nicht manuell angepasst werden. Da Repo/Owner für alle drei
Environments identisch sind, gilt diese Konfiguration environment-übergreifend.

### Automatische Ermittlung

`bootstrap.sh` erkennt vor dem Terraform-Lauf automatisch per GitHub CLI
(`gh repo view`, `gh api`), ob gegen GitHub.com oder GHES gearbeitet wird,
und exportiert die passenden Werte als `TF_VAR_github_*`-Umgebungsvariablen
(einmalig, unabhängig vom Environment/AWS-Profil, da Repo und Host für alle
drei Bootstrap-Läufe identisch sind). Terraform liest diese automatisch ein
– im Regelfall muss also keine der folgenden Dateien angefasst werden.

### Manuelle Konfiguration (Fallback)

Falls `gh` nicht verfügbar ist oder abweichende Werte gebraucht werden:
`terraform.tfvars.example` nach `terraform.tfvars` kopieren (wird von
`.gitignore` ignoriert, landet also nicht im Repo) und die Werte für das
jeweilige Szenario (gh.com oder GHES) eintragen.

## Variablen (`variables.tf`)

| Variable | Zweck |
|---|---|
| `environment` | `dev`, `test` oder `prod` – bestimmt u. a. den Namen des Infrastructure-State-Buckets (`infra-state-<environment>-<account-id>`). Wird von den Skripten automatisch als `TF_VAR_environment` gesetzt. |
| `enable_versioning` | Versioning für den Infrastructure-State-Bucket an/aus |
| `github_owner` | GitHub-Benutzer- oder Organisationsname. **Pflichtfeld, kein Default** – wird von `bootstrap.sh` automatisch gesetzt (siehe [Automatische Ermittlung](#automatische-ermittlung)) |
| `github_repo` | GitHub-Repository-Name. **Pflichtfeld, kein Default** – wird von `bootstrap.sh` automatisch gesetzt |
| `github_branch` | Branch, für den die Rolle per Trust-Policy erlaubt ist |
| `github_owner_id` | Immutable Owner-ID (nur gh.com) |
| `github_repo_id` | Immutable Repo-ID (nur gh.com) |
| `github_repo_id_ghes` | Repo-ID als separate Condition (GHES) |
| `github_oidc_provider_url` | OIDC-Token-Endpunkt (gh.com oder GHES) |

## Voraussetzungen

- **AWS CLI**, konfiguriert mit je einem Profil pro Environment (siehe
  [Environments und AWS-Profile](#environments-und-aws-profile)), berechtigt
  einen IAM OIDC Provider, eine IAM-Rolle samt Policy-Attachment und
  S3-Buckets im jeweiligen Account anzulegen.
- **Terraform** (`>= 1.5.0`, siehe `required_version` in `main.tf`).
- **GitHub CLI (`gh`)**, authentifiziert gegen den jeweiligen GitHub-Host
  (`gh auth login` bzw. bei GHES `gh auth login --hostname <ghes-host>`).
  Wird von `bootstrap.sh` genutzt, um automatisch zu erkennen, ob gegen
  GitHub.com oder GHES gearbeitet wird, und die passenden Terraform-Variablen
  zu setzen.
- **bash** sowie Standard-Tools wie `awk` (für die Shell-Skripte).

## Nutzung

Nicht direkt `terraform` in diesem Verzeichnis aufrufen, sondern über die
Skripte, da diese zusätzlich pro Environment den Bootstrap-State-Bucket
anlegen/leeren, das passende AWS-Profil setzen, die passende Backend-Config
übergeben und (bei `bootstrap.sh`) die GitHub-Variablen automatisch
ermitteln:

```bash
cd terraform/bootstrap
./bootstrap.sh          # bootstrappt dev, test und prod nacheinander
./destroy-bootstrap.sh  # baut alle drei Environments wieder ab (mit Bestätigung)
```

`bootstrap.sh`:

1. Ermittelt einmalig per GitHub CLI die GitHub-Variablen (owner/repo/host,
   siehe oben).
2. Läuft dann für jedes Environment (`dev`, `test`, `prod`):
   - prüft die AWS-Identität im jeweiligen Profil und ermittelt die
     Account-ID,
   - legt den Bootstrap-State-Bucket (`bootstrap-state-<environment>-<account-id>`)
     an, falls er noch nicht existiert (inkl. Versioning, SSE-Verschlüsselung,
     Public-Access-Block),
   - führt `terraform init -backend-config=envs/<environment>.backend.hcl
     -backend-config="bucket=bootstrap-state-<environment>-<account-id>"`,
     `validate`, `plan` und `apply` aus.

Danach sollten in **jedem** der drei AWS-Accounts der GitHub-OIDC-Provider,
die IAM-Rolle (`github-oidc-test`) und der zugehörige
Infrastructure-State-Bucket existieren.

`destroy-bootstrap.sh` räumt analog alles wieder ab – fragt vor dem ersten
Löschen eine einzige Bestätigung (`yes`) für **alle drei** Environments ab.

**Wichtig:** Die eigentliche Workload-Infrastruktur (`../hsr-dev/`,
`../hsr-test/`, `../hsr-prod/`) sollte vorher bereits separat zerstört sein,
da dieses Skript nur die Bootstrap-Ebene je Environment abbaut.

## Einzelnes Environment manuell bootstrappen/löschen

Für einen gezielten Lauf nur eines Environments (z. B. lokal debuggen)
lässt sich der jeweilige Terraform-Teil auch direkt aufrufen, ohne die
komplette Schleife:

```bash
cd terraform/bootstrap
export AWS_PROFILE=<aws-profile-dev>
export TF_VAR_environment=dev
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
terraform init \
  -backend-config=envs/dev.backend.hcl \
  -backend-config="bucket=bootstrap-state-dev-${ACCOUNT_ID}" \
  -reconfigure
terraform plan
terraform apply
```
