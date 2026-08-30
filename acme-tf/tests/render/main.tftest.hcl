# `terraform test`, not `check` blocks: a failed check is a WARNING and exits
# 0, so CI would go green on a broken render. A failed assert here fails.
#
#   terraform -chdir=acme-tf/tests/render init -backend=false
#   terraform -chdir=acme-tf/tests/render test

run "cloud_init_renders_correctly" {
  command = apply

  assert {
    condition     = output.assertions.postgres_password_intact
    error_message = "A '$' in the postgres password did not survive templatefile."
  }

  assert {
    condition     = output.assertions.django_secret_intact
    error_message = "A '$' in the Django secret key did not survive templatefile."
  }

  assert {
    condition     = output.assertions.fernet_key_intact
    error_message = "A '$' in the Fernet key did not survive templatefile."
  }

  assert {
    condition     = output.assertions.shell_expansion_intact
    error_message = "A shell expansion in the backup script was consumed by templatefile; it would run with an empty path."
  }

  assert {
    condition     = output.assertions.every_service_declared
    error_message = "A service is missing from the rendered compose file."
  }
}

run "the_gateway_is_the_only_ingress" {
  command = apply

  assert {
    condition     = output.assertions.published_port_count == 1
    error_message = "More than one service declares ports:. The gateway is the only ingress (C-12)."
  }

  assert {
    condition     = output.assertions.data_network_is_internal
    error_message = "The data network is not internal: true."
  }

  assert {
    condition     = output.assertions.no_route_to_microservice
    error_message = "A Traefik service points at svc-example. It must be reachable only from the BFF (C-12)."
  }

  assert {
    condition     = output.assertions.firewall_denies_by_default
    error_message = "ufw does not default-deny inbound."
  }

  assert {
    condition     = output.assertions.ssh_not_opened_to_internet
    error_message = "Port 22 is opened to the internet. SSH belongs on the tailnet."
  }
}

run "the_box_is_configured_correctly" {
  command = apply

  assert {
    condition     = output.assertions.data_volume_mounted
    error_message = "data_device was set but no mount was rendered; the database would land on the boot volume."
  }

  assert {
    condition     = output.assertions.acme_json_locked_down
    error_message = "acme.json is not chmod 600; Traefik refuses to use it and says so obscurely."
  }

  assert {
    condition     = output.assertions.gzipped_bytes < 32000
    error_message = "The gzipped cloud-init exceeds the 32 KB instance-metadata limit."
  }
}
