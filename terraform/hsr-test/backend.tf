terraform {
  backend "s3" {
    # TODO: <AWS_ACCOUNT_ID_TEST> durch die echte Account-ID des hsr-test-Accounts ersetzen.
    bucket       = "infra-state-test-497677369613"
    key          = "oidc-test/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
