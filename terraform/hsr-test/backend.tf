terraform {
  backend "s3" {
    bucket       = "infra_state_test"
    key          = "oidc-test/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
