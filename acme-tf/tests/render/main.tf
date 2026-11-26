# Renders the app-stack module with throwaway values, so template bugs are
# caught by `terraform validate`-time evaluation instead of at apply, on a real
# box, at the point where cloud-init has already half-run.
#
# What this catches, and has caught:
#   - a secret containing '$' corrupting the render (the replace(...) escaping)
#   - a template variable referenced but never passed
#   - a shell expansion written $${VAR} where Terraform eats one of the dollars
#
# Run: terraform -chdir=acme-tf/tests/render init -backend=false && \
#      terraform -chdir=acme-tf/tests/render apply -auto-approve
#
# There are no providers and no resources, so "apply" touches nothing.

terraform {
  required_version = ">= 1.5.0"
}

module "under_test" {
  source = "../../modules/app-stack"

  project     = "rendertest"
  domain_app  = "app.example.test"
  domain_apex = "example.test"
  acme_email  = "ops@example.test"

  # ghcr.io, and the same image names CI publishes. Not decoration: the deploy
  # derives the release's service list from the RENDERED compose file by
  # matching the registry host, so a fixture that renders `example.test/...`
  # makes that derivation come back empty and
  # .github/scripts/check-deploy-contract.sh has nothing to compare.
  image_gateway_auth = "ghcr.io/example/acme-gateway-auth:sha-0000000"
  image_bff          = "ghcr.io/example/acme-bff:sha-0000000"
  image_web          = "ghcr.io/example/acme-web:sha-0000000"
  image_svc_example  = "ghcr.io/example/acme-svc-example:sha-0000000"

  registry_username = "render-test"
  registry_token    = "render-test-token"

  # Every one of these deliberately contains a '$'. That is the whole point:
  # templatefile treats ${...} as interpolation, so without the escaping in
  # the module these either fail the render or silently corrupt the value that
  # lands on the box.
  postgres_password                  = "p$$w/rd+with=specials"
  rabbitmq_password                  = "r$bbit/mq+pass="
  django_secret_key                  = "dj$ngo-secret-key-$${NOT_INTERPOLATED}"
  jwt_private_key_b64                = "LS0tLS1CRUdJTiBQ$Uk1WQVRFIEtFWS0tLS0t"
  gateway_token                      = "gate$way-token"
  service_jwt_secret                 = "svc$jwt-secret"
  provider_credential_encryption_key = "fern3t$key-with-dollar="
  storage_access_key                 = "render-test-access"
  storage_secret_key                 = "render-test-secret"

  tailscale_authkey = "tskey-auth-$example"
  data_device       = "/dev/sdb"
}

output "cloud_init_bytes" {
  value = length(nonsensitive(module.under_test.cloud_init))
}

output "cloud_init_gzipped_bytes" {
  value = length(nonsensitive(module.under_test.cloud_init_gzipped))
}

# Booleans and counts rather than the rendered text itself: a test file that
# asserted on the content would have to receive it, and it contains every
# secret. These expose only the verdicts.
locals {
  rendered = nonsensitive(module.under_test.cloud_init)
}

output "assertions" {
  value = {
    # A '$' in a secret must survive templatefile unchanged. Escaping it, as
    # the common `replace(x, "$", "$$")` idiom does, silently doubles it.
    postgres_password_intact = strcontains(local.rendered, "p$$w/rd+with=specials")
    django_secret_intact     = strcontains(local.rendered, "dj$ngo-secret-key-$${NOT_INTERPOLATED}")
    fernet_key_intact        = strcontains(local.rendered, "fern3t$key-with-dollar=")

    # ${BACKUP_DIR} in the backup script is a SHELL expansion. If Terraform ate
    # the dollar, the script would run with an empty path and write to /.
    shell_expansion_intact = strcontains(local.rendered, "$${BACKUP_DIR}")

    # The other half of the same trap: templatefile only unescapes `$${`. A
    # `$$(` or `$$?` is left as written, and bash reads `$$` as its PID, so
    # `stamp="$$(date)"` names every dump `<pid>(date ...)`. Likewise compose
    # unescapes `$$` once, so `$$$$HOSTNAME` reaches the shell as `$$HOSTNAME`.
    no_doubled_shell_dollar = length(regexall("\\$\\$[(?]|\\$\\$\\$\\$", local.rendered)) == 0

    every_service_declared = alltrue([
      for service in ["traefik", "auth", "web", "bff", "worker", "svc-example", "postgres", "rabbitmq"] :
      strcontains(local.rendered, "${service}:")
    ])

    # C-12, asserted at render time so a second published port cannot reach a
    # box. Indentation-agnostic: the compose file is indented again when it is
    # embedded in the cloud-config.
    published_port_count = length(regexall("\n\\s+ports:\n", local.rendered))

    data_network_is_internal = strcontains(local.rendered, "internal: true")
    no_route_to_microservice = !strcontains(local.rendered, "http://svc-example:8000\"")

    data_volume_mounted        = strcontains(local.rendered, "/dev/sdb")
    firewall_denies_by_default = strcontains(local.rendered, "ufw default deny incoming")
    ssh_not_opened_to_internet = !strcontains(local.rendered, "ufw allow 22/tcp")
    acme_json_locked_down      = strcontains(local.rendered, "chmod 600 /opt/rendertest/acme/acme.json")

    # Most providers cap user_data at 32 KB. The gzipped form is what ships.
    gzipped_bytes = length(nonsensitive(module.under_test.cloud_init_gzipped))
  }
}

# The file the deploy script parses on the box:
#
#   terraform -chdir=acme-tf/tests/render output -raw compose_file > /tmp/c.yml
#   .github/scripts/check-deploy-contract.sh /tmp/c.yml
#
# That check derives the release's service list from this text using
# deploy-remote.sh's own code, and compares it with the list derived from the
# template. Two sources, two parsers — the deploy used to name its subjects by
# hand, and the hand-typed list was already missing one.
output "compose_file" {
  value = module.under_test.compose_file
}
