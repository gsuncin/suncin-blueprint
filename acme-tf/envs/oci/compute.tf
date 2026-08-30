data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = var.image_os
  operating_system_version = var.image_os_version
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
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

  tailscale_authkey  = var.tailscale_authkey
  sentry_dsn         = var.sentry_dsn
  sentry_environment = var.sentry_environment

  # Where the OCI paravirtualised volume attachment appears.
  data_device = var.data_volume_gb > 0 ? "/dev/oracleoci/oraclevdb" : ""
}

resource "oci_core_instance" "app" {
  count = var.enable_instance ? 1 : 0

  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = var.project
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gb
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.public.id
    # No ephemeral public IP. The RESERVED one below binds to the private IP
    # instead, which is what lets the instance be destroyed and recreated
    # without the DNS record ever changing.
    assign_public_ip = false
    nsg_ids          = [oci_core_network_security_group.app.id]
    hostname_label   = var.project
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand(var.ssh_public_key_path))
    # gzipped because the rendered cloud-init is well past the 32 KB metadata
    # limit, and the API's complaint about it names neither size nor field.
    user_data = module.app_stack.cloud_init_gzipped
  }

  lifecycle {
    ignore_changes = [
      # Without this, a newer Ubuntu image published upstream shows up as a
      # plan that DESTROYS AND RECREATES the box — which is a data-loss event
      # disguised as a routine apply. Rebuild deliberately, by tainting.
      source_details[0].source_id,
      # Same reasoning for cloud-init: it only runs on first boot, so a change
      # here has no effect on a running box but does propose replacing it.
      # Changes to the stack ship through the deploy script instead.
      metadata["user_data"],
    ]
  }
}

# --- Data volume ---------------------------------------------------------------
# Separate from the boot volume so the database survives rebuilding the machine.

resource "oci_core_volume" "data" {
  count = var.data_volume_gb > 0 ? 1 : 0

  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "${var.project}-data"
  size_in_gbs         = var.data_volume_gb

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_volume_attachment" "data" {
  count = var.enable_instance && var.data_volume_gb > 0 ? 1 : 0

  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.app[0].id
  volume_id       = oci_core_volume.data[0].id
  # Creates /dev/oracleoci/oraclevdb, which is the stable name cloud-init
  # formats and mounts. The kernel's /dev/sdb ordering is not stable.
  device = "/dev/oracleoci/oraclevdb"
}

# --- Reserved public IP ---------------------------------------------------------

data "oci_core_vnic_attachments" "app" {
  count = var.enable_instance ? 1 : 0

  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.app[0].id
}

data "oci_core_private_ips" "app" {
  count      = var.enable_instance ? 1 : 0
  vnic_id    = data.oci_core_vnic_attachments.app[0].vnic_attachments[0].vnic_id
  depends_on = [oci_core_instance.app]
}

resource "oci_core_public_ip" "app" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.project}-ip"
  lifetime       = "RESERVED"

  # Bound to the instance's PRIVATE ip. Detaching the instance
  # (enable_instance = false) releases the binding without releasing the
  # address, so the A record stays valid across a rebuild.
  private_ip_id = var.enable_instance ? data.oci_core_private_ips.app[0].private_ips[0].id : null

  lifecycle {
    # Losing this means a DNS change and waiting out the TTL, during an
    # incident, which is exactly when you can least afford it.
    prevent_destroy = true
  }
}
