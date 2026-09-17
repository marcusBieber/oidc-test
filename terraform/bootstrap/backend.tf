terraform {
  # Partial configuration: die eigentlichen Backend-Werte kommen aus
  # envs/<environment>.backend.hcl (per -backend-config beim init), da
  # dieses Verzeichnis pro Account/Environment (dev/test/prod) mit
  # jeweils eigenem Bootstrap-State-Bucket initialisiert wird.
  backend "s3" {}
}
