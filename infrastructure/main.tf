terraform {
  backend "gcs" {
    bucket = "hypertext-curfew-release-state"
    prefix = "lifecycle"
  }
  required_providers { google = { source = "hashicorp/google", version = "8.5.0" } }
}
provider "google" { project = "hypertext-curfew-release" }
module "hosting" {
  source = "git::https://github.com/TheHypertextStudio/release-engineering.git//infra/modules/hosting?ref=83e35d9382bdfa6470fbdd84e033f8488e325e78"
  project_id = "hypertext-studio-releases"
  bucket = "hypertext-studio-releases"
  region = "US"
}
module "curfew" {
  depends_on = [module.hosting]
  source = "git::https://github.com/TheHypertextStudio/release-engineering.git//infra/modules/product?ref=83e35d9382bdfa6470fbdd84e033f8488e325e78"
  project_id = "hypertext-curfew-release"
  product = "curfew"
  region = "us-central1"
  distribution_bucket = module.hosting.bucket
  repository_id = "1165282307"
  owner_id = "170363390"
  default_branch = "main"
  tooling_revision = jsondecode(file("${path.module}/../studio.lock.json")).revision
  credential_names = ["apple-certificate-base64", "apple-certificate-password", "apple-api-private-key", "apple-api-key-id", "apple-api-issuer", "sparkle-private-key", "pin-updates-key", "apple-provisioning-profiles"]
  pin_update_credential_names = ["pin-updates-key"]
  promotion_credential_names = ["apple-api-private-key", "apple-api-key-id", "apple-api-issuer"]
}
output "curfew" { value = module.curfew }
