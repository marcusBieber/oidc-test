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

# Nur relevant für GitHub.com mit Immutable Subject Claims.
# Bei GitHub Enterprise Server einfach null lassen.
variable "github_owner_id" {
  description = "Immutable Owner-ID (nur GitHub.com, nicht bei GHES verfügbar)"
  type        = string
  default     = 180164030  #null
}

variable "github_repo_id" {
  description = "Immutable Repo-ID (nur GitHub.com, nicht bei GHES verfügbar)"
  type        = string
  default     = 1361295306  #null
}

variable "github_repo_id_ghes" {
  description = "Repository-ID des GHES-Repos (für zusätzliche repository_id-Bedingung, verhindert Namens-Recycling-Risiko)"
  type        = string
  default     = null
}
