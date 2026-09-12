# oidc-test

Testprojekt für eine **keyless AWS-Anbindung von GitHub Actions per OpenID
Connect (OIDC)**: Statt langlebiger AWS Access Keys als GitHub Secret nutzt
die CI-Pipeline ein kurzlebiges, von GitHub signiertes Token, das AWS gegen
eine IAM-Rolle eintauscht (`sts:AssumeRoleWithWebIdentity`). Das Repo enthält
sowohl die einmalige Grundlagen-Infrastruktur (OIDC-Provider, IAM-Rolle,
State-Buckets) als auch ein minimales Testmodul, das über genau diese Rolle
provisioniert wird, um den kompletten Weg zu verifizieren.

Unterstützt werden sowohl **GitHub.com** als auch **GitHub Enterprise Server
(GHES)** als OIDC-Identitätsanbieter.

## Überblick / Funktionsweise

Das Setup ist zweistufig aufgebaut:

1. **Bootstrap** (`terraform/bootstrap/`): Legt einmalig die Grundlage an –
   OIDC-Provider, IAM-Rolle mit Trust-Policy (eingeschränkt auf Repo/Branch)
   und den S3-Bucket, in dem der State der eigentlichen Infrastruktur liegt.
   Wird lokal per Skript ausgeführt (siehe unten), **nicht** über GitHub
   Actions – die CI-Rolle existiert ja erst danach.
2. **Infrastruktur** (`terraform/`): Ein minimales Testmodul (aktuell: ein
   S3-Bucket), das über die im Bootstrap angelegte IAM-Rolle per GitHub
   Actions provisioniert wird. Dient nur dem Nachweis, dass die OIDC-Kette
   funktioniert.

Details zu den beiden Terraform-Verzeichnissen stehen in den jeweiligen
READMEs:
- [`terraform/README.md`](terraform/README.md)
- [`terraform/bootstrap/README.md`](terraform/bootstrap/README.md)

## Voraussetzungen

Um den Code zu nutzen, werden benötigt:

- **AWS CLI**, konfiguriert mit einer Identität, die berechtigt ist, einen
  IAM OIDC Provider, eine IAM-Rolle samt Policy-Attachment und S3-Buckets
  anzulegen (nur für den einmaligen Bootstrap-Schritt nötig).
- **Terraform** (`>= 1.5.0`, siehe `required_version` in den `.tf`-Dateien).
- **GitHub CLI (`gh`)**, authentifiziert gegen den jeweiligen GitHub-Host
  (`gh auth login` bzw. bei GHES `gh auth login --hostname <ghes-host>`).
  Wird von `bootstrap.sh` genutzt, um automatisch zu erkennen, ob gegen
  GitHub.com oder GHES gearbeitet wird, und die passenden Terraform-Variablen
  zu setzen.
- **bash** sowie Standard-Tools wie `awk` (für die Shell-Skripte).
- Ein AWS-Account, in dem die Ressourcen angelegt werden dürfen (aktuell fest
  auf Region `eu-central-1` und Account `798836978111` ausgelegt, sichtbar an
  Bucket-Namen/ARNs in den `.tf`-Dateien).

## Repo-Struktur

```
.
├── bootstrap.sh                  # Legt die Bootstrap-Infrastruktur an
├── destroy-bootstrap.sh          # Reißt die Bootstrap-Infrastruktur wieder ab
├── .github/workflows/
│   ├── test-oidc.yml             # Reiner OIDC-Verbindungstest
│   └── terraform-s3.yml          # Führt terraform/ (Infrastruktur) per CI aus
└── terraform/
    ├── main.tf, backend.tf       # Test-Infrastruktur (S3-Bucket)
    └── bootstrap/
        ├── main.tf, variables.tf, backend.tf, outputs.tf
        └── terraform.tfvars.example
```

## Die Shell-Skripte

### `bootstrap.sh`

Richtet die komplette Bootstrap-Infrastruktur ein:

1. Prüft die aktuelle AWS-Identität (`aws sts get-caller-identity`).
2. Ermittelt automatisch per GitHub CLI, ob das Repo auf GitHub.com oder GHES
   liegt, und leitet daraus Owner-/Repo-ID, Repo-Name und die passende
   OIDC-Provider-URL ab (siehe
   [`terraform/bootstrap/README.md`](terraform/bootstrap/README.md) für
   Details). Diese Werte werden als `TF_VAR_*`-Umgebungsvariablen exportiert,
   sodass danach kein manuelles Anpassen von `.tfvars` nötig ist.
3. Legt den Bootstrap-State-Bucket an (falls er noch nicht existiert),
   inklusive Versioning, SSE-Verschlüsselung und Public-Access-Block.
4. Führt `terraform init/validate/plan/apply` im Verzeichnis
   `terraform/bootstrap` aus.

Danach sollten der GitHub-OIDC-Provider, die IAM-Rolle
(`github-oidc-test`) und der Infrastructure-State-Bucket in AWS existieren.

### `destroy-bootstrap.sh`

Räumt alles wieder ab, was `bootstrap.sh` angelegt hat:

1. Prüft AWS-Identität und fragt eine explizite Bestätigung (`yes`) ab, bevor
   irgendetwas gelöscht wird.
2. Leert vollständig den Infrastructure-State-Bucket (alle Objektversionen
   und Delete Marker), damit Terraform ihn im nächsten Schritt löschen kann.
3. Führt `terraform destroy` im Bootstrap-Verzeichnis aus (OIDC-Provider,
   IAM-Rolle, Infrastructure-State-Bucket werden entfernt).
4. Leert und löscht anschließend auch den Bootstrap-State-Bucket selbst
   (inkl. Retry, da S3 kurzzeitig noch „BucketNotEmpty“ melden kann).

**Wichtig:** Die eigentliche Test-Infrastruktur (`terraform/`) sollte vorher
bereits separat zerstört sein (z. B. `terraform -chdir=terraform destroy`),
da dieses Skript nur die Bootstrap-Ebene abbaut.

## Nutzung / Ablauf

1. **Voraussetzungen** aus dem Abschnitt oben sicherstellen (`aws`,
   `terraform`, `gh` installiert und eingeloggt).
2. **Bootstrap ausführen:**
   ```bash
   ./bootstrap.sh
   ```
   Legt OIDC-Provider, IAM-Rolle und State-Bucket an.
3. **OIDC-Verbindung testen:** Workflow `Test AWS OIDC`
   (`.github/workflows/test-oidc.yml`) manuell in GitHub Actions auslösen
   (`workflow_dispatch`) – prüft nur, ob die Rolle übernommen werden kann.
4. **Test-Infrastruktur provisionieren:** Workflow `Terraform S3 Test`
   (`.github/workflows/terraform-s3.yml`) manuell auslösen – führt
   `terraform init/validate/plan/apply` im Verzeichnis `terraform/` aus und
   legt den Test-S3-Bucket an.
5. **Aufräumen:**
   - Test-Infrastruktur zuerst separat zerstören (`terraform -chdir=terraform
     destroy` bzw. über einen entsprechenden Workflow-Schritt).
   - Danach Bootstrap-Ebene abbauen:
     ```bash
     ./destroy-bootstrap.sh
     ```

## GitHub Actions Workflows

Beide Workflows sind manuell auslösbar (`workflow_dispatch`) und benötigen
`permissions: id-token: write`, damit GitHub Actions ein OIDC-Token ausstellen
kann:

- **`test-oidc.yml`** – übernimmt nur die Rolle `github-oidc-test` und ruft
  `aws sts get-caller-identity` auf. Reiner Verbindungstest ohne Terraform.
- **`terraform-s3.yml`** – übernimmt dieselbe Rolle und führt Terraform im
  Verzeichnis `terraform/` aus, um den Test-Bucket zu erstellen.

Die Rolle wird aktuell per ARN referenziert
(`arn:aws:iam::798836978111:role/github-oidc-test`) – bei Wiederverwendung
für ein anderes AWS-Konto muss dieser ARN in beiden Workflow-Dateien
angepasst werden.
