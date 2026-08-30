# acme-tf

One Ubuntu VPS, Docker Compose, a data volume, backups and a firewall.

```
modules/app-stack/   Provider-agnostic: renders cloud-init, the compose file
                     and the Traefik routers from one set of variables
envs/oci/            Reference implementation: VCN, NSG, A1 instance,
                     data volume, reserved IP
envs/existing-host/  The same stack onto a VPS you already have, any provider
tests/render/        Renders the templates and asserts on the result
```

The stack definition is shared. Only the machine differs between environments,
which is what stops the two drifting.

## Quick start

```bash
cd envs/oci
cp terraform.tfvars.example terraform.tfvars   # fill in, gitignored
set -a; source .env; set +a                    # secrets as TF_VAR_*, never inline
terraform init
terraform plan -out=tf.plan
terraform apply tf.plan
```

Then point the A records that `terraform output dns_records_required` names at
the output IP. **Certificates cannot be issued before those resolve** — the
HTTP-01 challenge has to reach the box.

## Checks

```bash
terraform fmt -check -recursive .
terraform -chdir=tests/render init -backend=false
terraform -chdir=tests/render test
```

The render tests are the valuable ones. They evaluate the templates with
throwaway values and assert on the output, so a template bug is caught here
rather than on a machine that has already half-booted. They currently assert
that a `$` in a secret survives, that a shell expansion was not eaten, that
exactly one service publishes a port, that the data network is internal, and
that the result still fits in instance metadata.

## Things that are load-bearing

| Pattern | Why |
|---|---|
| `base64gzip(templatefile(...))` | The rendered cloud-init is ~26 KB and the metadata limit is 32 KB; the API's complaint names neither size nor field |
| **No** `replace(secret, "$", "$$")` | The common escaping idiom is a bug — see below |
| `urlencode()` in connection URLs | Generated passwords contain `/ + =`, which change how a URL parses |
| Reserved IP bound to the **private** IP | Destroy and recreate the box without touching DNS |
| `ignore_changes = [source_details[0].source_id]` | A newer upstream image otherwise plans a DESTROY of your database host |
| `prevent_destroy` on the IP and the data volume | The two things you cannot recreate |
| NSG opens 80/443 and **not 22** | SSH arrives over Tailscale, which needs only egress |
| `0600` on every file with a secret | The compose file is `0644` and readable by anyone on the box |
| systemd units, not `cron.d` | `systemctl status`, `journalctl -u`, and failure state for free |

### The `$`-escaping idiom is wrong

You will see this in a lot of Terraform, and it is a bug:

```hcl
postgres_password = replace(var.postgres_password, "$", "$$")   # NO
```

`templatefile` interpolates the **template's** `${...}` markers. It does not
re-interpolate the values you substitute in. Verified against Terraform 1.14:

```
secret = "p$w/rd"                                 7 chars
templatefile(t, {v = secret})                     7 chars, identical
templatefile(t, {v = replace(secret, "$", "$$")}) 9 chars, CORRUPTED
```

So the escaping does not protect anything — it silently doubles every dollar,
and the password on the box stops matching the one in your password manager.
The failure surfaces as an authentication error on a freshly provisioned
machine.

What *does* need escaping is a literal `${...}` inside a template **file**, and
that is handled there with `$${...}` — see the backup script.

## State

The backend block in `envs/oci/versions.tf` is commented out so that
`init -backend=false && validate` runs in CI with no credentials. **Uncomment
it before you use this for real.**

State holds every `sensitive` variable in plaintext, including the whole
rendered cloud-init. Local state on a laptop is unshareable, unlocked, and one
lost machine from unrecoverable.

## Rollback

`terraform apply` is not how you roll back an application deploy — that is
`.github/workflows/deploy-prod.yml`, which captures the running image digests
before it pulls and restores them if the new containers do not become healthy.

Terraform rolls back *infrastructure*. For an application problem, redeploy the
previous immutable tag.

A **non-backward-compatible migration** is the case neither handles: forcing
old code onto a new schema is worse than the outage. Restore from backup. This
is why C-9 requires migrations to be additive within a release.
