# Provision a VPS you already have.
#
# For anyone not on OCI: bring an Ubuntu 24.04 host with SSH access and a
# public IP, and this configures it identically to envs/oci. The stack
# definition is shared — only the machine differs.
#
# What this does NOT do is manage the machine's lifecycle. It has no idea how
# the host was created and cannot recreate it. That is the trade for working
# with any provider.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
  }
}

variable "host" {
  description = "IP or hostname to configure. A tailnet address is preferable to a public one."
  type        = string
}

variable "ssh_user" {
  type    = string
  default = "ubuntu"
}

variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519"
}

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

variable "storage_access_key" {
  description = "Object store access key, and MinIO's root user."
  type        = string
  sensitive   = true
}

variable "storage_secret_key" {
  description = "Object store secret key, and MinIO's root password."
  type        = string
  sensitive   = true
}

variable "data_device" {
  description = "Block device for the data volume, e.g. /dev/sdb. Empty stores data on the root filesystem, which is only acceptable for a throwaway environment."
  type        = string
  default     = ""
}

module "app_stack" {
  source = "../../modules/app-stack"

  project     = var.project
  domain_app  = var.domain_app
  domain_apex = var.domain_apex
  acme_email  = var.acme_email

  image_gateway_auth = var.image_gateway_auth
  image_bff          = var.image_bff
  image_web          = var.image_web
  image_svc_example  = var.image_svc_example

  registry_username = var.registry_username
  registry_token    = var.registry_token

  postgres_password                  = var.postgres_password
  rabbitmq_password                  = var.rabbitmq_password
  django_secret_key                  = var.django_secret_key
  jwt_private_key_b64                = var.jwt_private_key_b64
  gateway_token                      = var.gateway_token
  service_jwt_secret                 = var.service_jwt_secret
  provider_credential_encryption_key = var.provider_credential_encryption_key

  storage_access_key = var.storage_access_key
  storage_secret_key = var.storage_secret_key
  data_device        = var.data_device
}

resource "null_resource" "provision" {
  # Re-runs when the rendered configuration changes. Note that cloud-init only
  # executes once per machine, so this path uses `cloud-init single` to apply
  # the same file to a host that has already booted.
  triggers = {
    cloud_init = sha256(module.app_stack.cloud_init)
  }

  connection {
    type        = "ssh"
    host        = var.host
    user        = var.ssh_user
    private_key = file(pathexpand(var.ssh_private_key_path))
  }

  provisioner "file" {
    content     = module.app_stack.cloud_init
    destination = "/tmp/${var.project}-cloud-init.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      # 0600 before it moves anywhere readable: the file contains every secret
      # in plaintext, and /tmp is world-readable.
      "chmod 600 /tmp/${var.project}-cloud-init.yaml",
      "sudo mv /tmp/${var.project}-cloud-init.yaml /var/lib/cloud/seed-${var.project}.yaml",
      "sudo cloud-init single --name cc_write_files --frequency always --file /var/lib/cloud/seed-${var.project}.yaml",
      "sudo cloud-init single --name cc_runcmd --frequency always --file /var/lib/cloud/seed-${var.project}.yaml",
      "sudo bash /var/lib/cloud/instance/scripts/runcmd || true",
    ]
  }
}

output "next_steps" {
  value = <<-EOT
    Point these A records at ${var.host}, then wait for the certificate:
      ${var.domain_app}
      ${var.domain_apex}
      www.${var.domain_apex}

    Certificates cannot be issued before the names resolve — the HTTP-01
    challenge has to reach this box.

    Check progress with:
      ssh ${var.ssh_user}@${var.host} 'cat /opt/${var.project}/deploy-status'
      ssh ${var.ssh_user}@${var.host} 'sudo docker compose -f /opt/${var.project}/docker-compose.yml ps'
  EOT
}
