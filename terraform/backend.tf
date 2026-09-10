terraform {
  backend "s3" {
    bucket       = "marcus-infrastructure-tfstate-798836978111"
    key          = "oidc-test/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
