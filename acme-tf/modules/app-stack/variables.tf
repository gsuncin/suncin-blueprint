variable "project" {
  description = "Short project slug. Names the install directory, the systemd units and the log tag."
  type        = string
  default     = "acme"
}

variable "domain_app" {
  description = "Host for the authenticated SPA and the API, e.g. app.example.com."
  type        = string
}

variable "domain_apex" {
  description = "Host for the public landing page. www.<apex> is derived, not configured."
  type        = string
}

variable "acme_email" {
  description = "Contact address Let's Encrypt uses for expiry warnings."
  type        = string
}

# --- Images -----------------------------------------------------------------
# Immutable tags. Never `:latest` — a box that pulled `latest` cannot tell you
# what it is running, and two boxes that pulled it on different days disagree.
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

# --- Datastores --------------------------------------------------------------
variable "postgres_version" {
  type    = string
  default = "16-alpine"
}

variable "postgres_db" {
  type    = string
  default = "acme"
}

variable "postgres_user" {
  type    = string
  default = "acme"
}

variable "postgres_password" {
  type      = string
  sensitive = true
}

variable "rabbitmq_user" {
  type    = string
  default = "acme"
}

variable "rabbitmq_password" {
  type      = string
  sensitive = true
}

# --- Application secrets ------------------------------------------------------
variable "django_secret_key" {
  type      = string
  sensitive = true
}

variable "jwt_private_key_b64" {
  description = "RS256 signing key, PEM base64-encoded onto one line. The gateway needs only the public half, which it fetches from the JWKS endpoint."
  type        = string
  sensitive   = true
}

variable "gateway_token" {
  description = "Shared between the gateway and the BFF so a compromised container on the edge network cannot forge identity headers."
  type        = string
  sensitive   = true
}

variable "service_jwt_secret" {
  description = "HS256 secret the BFF uses to mint 60-second tokens for the microservice."
  type        = string
  sensitive   = true
}

variable "provider_credential_encryption_key" {
  description = "Fernet key for per-tenant provider credentials at rest. NEVER shared across environments: a staging leak must not decrypt production."
  type        = string
  sensitive   = true
}

# --- Optional observability ---------------------------------------------------
variable "sentry_dsn" {
  type      = string
  default   = ""
  sensitive = true
}

variable "sentry_environment" {
  type    = string
  default = "production"
}

variable "loki_url" {
  type    = string
  default = ""
}

variable "loki_username" {
  type      = string
  default   = ""
  sensitive = true
}

variable "loki_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "tailscale_authkey" {
  description = "Reusable, not single-use: a single-use key is consumed on first boot, so a rebuild of the box joins nothing and you lose SSH."
  type        = string
  default     = ""
  sensitive   = true
}

variable "data_device" {
  description = "Block device for the data volume. Empty means store data on the boot volume, which is only acceptable for a throwaway environment."
  type        = string
  default     = ""
}

variable "backup_retention_days" {
  type    = number
  default = 14
}
