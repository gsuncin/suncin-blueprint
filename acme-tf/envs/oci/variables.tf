# --- OCI account and placement ------------------------------------------------
variable "tenancy_ocid" { type = string }
variable "user_ocid" { type = string }
variable "fingerprint" { type = string }
variable "private_key_path" { type = string }
variable "region" { type = string }
variable "compartment_ocid" { type = string }

variable "ssh_public_key_path" {
  description = "Injected into the image's authorized_keys. SSH still arrives over Tailscale; this is the break-glass path through the provider's console."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

# --- Network -------------------------------------------------------------------
variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

# --- Instance ------------------------------------------------------------------
variable "enable_instance" {
  description = "Flip to false to detach the instance while keeping the reserved IP and the DNS record that points at it. That is the whole blue/green story on one box."
  type        = bool
  default     = true
}

variable "instance_shape" {
  type    = string
  default = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  type    = number
  default = 2
}

variable "instance_memory_gb" {
  type    = number
  default = 12
}

variable "boot_volume_gb" {
  type    = number
  default = 50
}

variable "data_volume_gb" {
  description = "A dedicated volume for Postgres. Keeping the database off the boot volume is what makes rebuilding the box a routine operation rather than a restore-from-backup."
  type        = number
  default     = 50
}

variable "image_os" {
  type    = string
  default = "Canonical Ubuntu"
}

variable "image_os_version" {
  type    = string
  default = "24.04"
}

# --- Passed through to the app-stack module ------------------------------------
variable "project" {
  type    = string
  default = "acme"
}
variable "domain_app" { type = string }
variable "domain_apex" { type = string }
variable "acme_email" { type = string }

variable "image_gateway_auth" { type = string }
variable "image_bff" { type = string }
variable "image_web" { type = string }
variable "image_svc_example" { type = string }

variable "registry_username" {
  type      = string
  sensitive = true
}
variable "registry_token" {
  type      = string
  sensitive = true
}

variable "postgres_password" {
  type      = string
  sensitive = true
}
variable "rabbitmq_password" {
  type      = string
  sensitive = true
}
variable "django_secret_key" {
  type      = string
  sensitive = true
}
variable "jwt_private_key_b64" {
  type      = string
  sensitive = true
}
variable "gateway_token" {
  type      = string
  sensitive = true
}
variable "service_jwt_secret" {
  type      = string
  sensitive = true
}
variable "provider_credential_encryption_key" {
  type      = string
  sensitive = true
}

variable "tailscale_authkey" {
  description = "Use a REUSABLE key. A single-use key is consumed on first boot, so rebuilding the box joins nothing and you have locked yourself out."
  type        = string
  default     = ""
  sensitive   = true
}

variable "sentry_dsn" {
  type      = string
  default   = ""
  sensitive = true
}
variable "sentry_environment" {
  type    = string
  default = "production"
}
