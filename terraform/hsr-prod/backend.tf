terraform {
  backend "s3" {
    # TODO: <AWS_ACCOUNT_ID_PROD> durch die echte Account-ID des hsr-prod-Accounts ersetzen.
    bucket       = "infra-state-prod-<AWS_ACCOUNT_ID_PROD>"
    key          = "oidc-test/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
