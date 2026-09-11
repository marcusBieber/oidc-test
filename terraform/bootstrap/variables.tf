variable "enable_versioning" {
  description = "Aktiviert Versioning für die State-Buckets"
  type        = bool
  default     = true
}

variable "github_owner" {
  description = "GitHub Benutzer- oder Organisationsname"
  type        = string
  default     = "marcusBieber"
}

variable "github_repo" {
  description = "GitHub Repository-Name"
  type        = string
  default     = "oidc-test"
}

variable "github_branch" {
  description = "Branch, für den die OIDC-Rolle erlaubt ist"
  type        = string
  default     = "main"
}

# GitHub.com und GHES verwenden unterschiedliche Mechanismen, um das
# Namens-Recycling-Risiko (gelöschtes/umbenanntes Repo, Name wird neu
# vergeben) in der Trust-Policy abzudecken. Konkrete Werte gehören in eine
# lokale, nicht eingecheckte terraform.tfvars (siehe terraform.tfvars.example)
# oder werden von bootstrap.sh automatisch per GitHub CLI ermittelt.
#
# GitHub.com (Immutable Subject Claims): github_owner_id + github_repo_id setzen.
# GitHub Enterprise Server: beide auf null lassen und stattdessen
# github_repo_id_ghes befüllen.
variable "github_owner_id" {
  description = "Immutable Owner-ID (nur GitHub.com, nicht bei GHES verfügbar)"
  type        = string
  default     = null
}

variable "github_repo_id" {
  description = "Immutable Repo-ID (nur GitHub.com, nicht bei GHES verfügbar)"
  type        = string
  default     = null
}

variable "github_repo_id_ghes" {
  description = "Repository-ID des GHES-Repos (für zusätzliche repository_id-Bedingung, verhindert Namens-Recycling-Risiko)"
  type        = string
  default     = null
}

variable "github_oidc_provider_url" {
  description = "OIDC-Token-Endpunkt des GitHub-Actions-Anbieters. gh.com: https://token.actions.githubusercontent.com. GHES: https://<ghes-host>/_services/token (Pfad je nach GHES-Konfiguration prüfen)."
  type        = string
  default     = "https://token.actions.githubusercontent.com"
}
