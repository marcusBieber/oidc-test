terraform {
  backend "s3" {
    bucket       = "infra-state-prod"
    key          = "oidc-test/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
