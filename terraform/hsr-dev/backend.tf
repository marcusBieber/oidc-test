terraform {
  backend "s3" {
    # TODO: <AWS_ACCOUNT_ID_DEV> durch die echte Account-ID des hsr-dev-Accounts ersetzen.
    bucket       = "infra-state-dev-798836978111"
    key          = "oidc-test/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
