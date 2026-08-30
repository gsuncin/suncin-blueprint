---
name: project-infrastructure
description: Use when working on Terraform, cloud-init, Traefik configuration, Docker Compose, deployment scripts, or GitHub Actions workflows in this monorepo.
---

# Infrastructure

Target: **one Ubuntu VPS**, Docker Compose, one Postgres, no blue/green, no
load balancer. If a change implies a second host, say so rather than quietly
provisioning it.

## Terraform

Always from the repo root, with `-chdir`:

```bash
set -a; source acme-tf/.env; set +a          # never inline secrets in a script
terraform -chdir=acme-tf/envs/oci init
terraform -chdir=acme-tf/envs/oci plan -out=tf.plan
```

- **Never commit state or a plan.** A `.tfplan` embeds the whole state
  including `user_data` in plaintext. Untracking one does not unpublish it.
- Before a structural refactor, `plan` must show **no diff**.
- You produce the plan for production. You do not `apply` to it.

## The escaping rules that bite

| Rule | Why |
|---|---|
| `replace(var.secret, "$", "$$")` before `templatefile` | `templatefile` interprets `${...}`; a `$` in a secret corrupts the render |
| `$${VAR:-default}` inside a templated shell script | Doubles the `$` so the shell, not Terraform, expands it |
| `urlencode()` on credentials in a connection URL | Generated passwords contain `/ + =`, which break `amqp://` parsing |
| `base64gzip(templatefile(...))` for user_data | The rendered cloud-init exceeds the 32 KB metadata limit |

## cloud-init

- File modes: `0644` config, **`0600` anything containing a secret**, `0755`
  scripts, `chmod 700` on the secrets directory.
- **Secrets go in a `0600` env file; non-secrets go inline in `environment:`.**
  The compose file is world-readable on the box.
- `touch` any log file a watcher will open before starting the watcher —
  fail2ban's jail races whatever would otherwise create it.
- Deploy scripts log through `exec > >(tee -a "$log" | logger -t <tag> -s)` and
  `trap ... ERR` a machine-readable status breadcrumb.

## Deployment

- **Exactly one container publishes a port.** `./scripts/verify-isolation.sh`
  asserts it and runs in CI.
- Deploy an **immutable tag** (`sha-<commit>` or semver) passed as a parameter.
- **`< /dev/null` on every command in a `bash -s` script** that could consume
  stdin — `docker compose run` will otherwise eat the rest of the script and
  exit 0 halfway through.
- Wait for `.State.Health.Status = healthy` **before** reloading the proxy;
  recreated containers have new IPs.

## CI

- Test workflows are `workflow_call` only. A second trigger makes two runs share
  the concurrency group and one gets cancelled — a permanently red check that
  people learn to ignore.
- The image build has `needs: tests`. Red suite ⇒ no image ⇒ no deploy.
- `push: ${{ github.event_name == 'push' }}` — PRs build but never publish.
- Keep path filters: a frontend change should not run Terraform checks.
