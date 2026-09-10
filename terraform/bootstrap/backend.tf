terraform {
  backend "s3" {
    bucket       = "marcus-bootstrap-tfstate-798836978111"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}


