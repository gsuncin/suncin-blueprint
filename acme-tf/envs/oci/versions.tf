terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }

  # State holds every `sensitive` variable in PLAINTEXT, including the rendered
  # cloud-init with all its secrets. Local state on an operator's laptop is one
  # lost machine from unrecoverable and cannot be shared or locked.
  #
  # Configure this from backend.hcl, which is gitignored:
  #   terraform init -backend-config=backend.hcl
  #
  # Commented out so `init -backend=false && validate` works in CI with no
  # credentials. Uncomment for real use.
  #
  # backend "s3" {
  #   # OCI Object Storage speaks the S3 API. Any S3-compatible store works.
  #   key                         = "acme/terraform.tfstate"
  #   region                      = "sa-saopaulo-1"
  #   skip_region_validation      = true
  #   skip_credentials_validation = true
  #   skip_requesting_account_id  = true
  #   skip_metadata_api_check     = true
  #   skip_s3_checksum            = true
  #   use_lockfile                = true
  # }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = pathexpand(var.private_key_path)
  region           = var.region
}
