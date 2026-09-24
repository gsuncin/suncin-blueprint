locals {
  # NO $-ESCAPING HERE, DELIBERATELY.
  #
  # The widespread `replace(var.secret, "$", "$$")` before templatefile is a
  # cargo-culted bug. templatefile interpolates the TEMPLATE's own ${...}
  # markers; it does not re-interpolate the values you substitute in. Verified
  # with Terraform 1.14:
  #
  #   secret = "p$w/rd"                        (7 chars)
  #   templatefile(t, {v = secret})            -> 7 chars, identical
  #   templatefile(t, {v = replace(secret,     -> 9 chars, CORRUPTED
  #                                "$", "$$")})
  #
  # So escaping does not protect a secret containing '$' — it silently doubles
  # every dollar, and the password written to the box stops matching the one in
  # your password manager. The failure surfaces as an authentication error on a
  # freshly provisioned machine, which is a miserable thing to debug.
  #
  # What DOES need escaping is literal ${...} inside the template FILES, and
  # that is handled there with $${...} — see the backup script.

  # urlencode because generated passwords routinely contain '/', '+' and '=',
  # every one of which changes how a URL parses. kombu splits on them and ends
  # up with a broker host that does not exist.
  celery_broker_url = "amqp://${urlencode(var.rabbitmq_user)}:${urlencode(var.rabbitmq_password)}@rabbitmq:5672//"

  compose_file = templatefile("${path.module}/templates/docker-compose.yml.tftpl", {
    project            = var.project
    postgres_version   = var.postgres_version
    minio_version      = var.minio_version
    image_gateway_auth = var.image_gateway_auth
    image_bff          = var.image_bff
    image_web          = var.image_web
    image_svc_example  = var.image_svc_example
    data_root          = var.data_device == "" ? "/opt/${var.project}/data" : "/mnt/data"
  })

  traefik_routers = templatefile("${path.module}/templates/routers.yml.tftpl", {
    domain_app  = var.domain_app
    domain_apex = var.domain_apex
  })

  cloud_init = templatefile("${path.module}/templates/user-data.yaml.tftpl", merge({
    postgres_password                  = var.postgres_password
    rabbitmq_password                  = var.rabbitmq_password
    django_secret_key                  = var.django_secret_key
    jwt_private_key_b64                = var.jwt_private_key_b64
    gateway_token                      = var.gateway_token
    service_jwt_secret                 = var.service_jwt_secret
    provider_credential_encryption_key = var.provider_credential_encryption_key
    storage_access_key = var.storage_access_key
    storage_secret_key = var.storage_secret_key
    sentry_dsn                         = var.sentry_dsn
    loki_password                      = var.loki_password
    registry_token                     = var.registry_token
    tailscale_authkey                  = var.tailscale_authkey

    project               = var.project
    domain_app            = var.domain_app
    domain_apex           = var.domain_apex
    acme_email            = var.acme_email
    postgres_db           = var.postgres_db
    postgres_user         = var.postgres_user
    rabbitmq_user         = var.rabbitmq_user
    registry_username     = var.registry_username
    celery_broker_url     = local.celery_broker_url
    sentry_environment    = var.sentry_environment
    loki_url              = var.loki_url
    loki_username         = var.loki_username
    data_device           = var.data_device
    backup_retention_days = var.backup_retention_days

    # Indented to sit under a write_files `content: |` block.
    compose_file    = indent(6, local.compose_file)
    traefik_routers = indent(6, local.traefik_routers)
    traefik_static  = indent(6, templatefile("${path.module}/templates/traefik.yml.tftpl", { acme_email = var.acme_email }))
    middlewares     = indent(6, file("${path.module}/../../../acme-gateway/traefik/dynamic/middlewares.yml"))
  }))
}
