# Deploying

## First time

Terraform provisions the box and cloud-init brings the stack up once:

```bash
cd acme-tf/envs/oci
set -a; source .env; set +a
terraform init && terraform apply
```

Watch it land:

```bash
tailscale ssh ubuntu@acme
sudo cat /opt/acme/deploy-status          # machine-readable breadcrumb
sudo tail -f /var/log/acme-first-boot.log
cloud-init status --long
```

Point the A records at the output IP. Traefik requests certificates once the
names resolve — not before, because the HTTP-01 challenge has to reach the box.

## Every time after

`.github/workflows/deploy-prod.yml`, triggered by a successful image build on
`main` or run by hand with a tag.

What it does, and why each step is in that order:

1. **Joins the tailnet**, then SSHes to a `100.x` address. This is why the
   security group can open 80/443 and nothing else.
2. **Streams `deploy-remote.sh`** from the repo. The script is reviewed like any
   other code and nothing deploy-related is pre-installed on the box, so the box
   cannot drift from the repo.
3. **Refuses `latest`.** A box running `latest` cannot tell you what it is
   running.
4. **Records the running image digests** for rollback.
5. **Migrates before swapping containers.** The old code is still serving, and
   migrations are additive within a release (C-9), so it keeps working against
   the new schema for the seconds in between. Once, here — not in an entrypoint,
   where N starting containers race the lock.
6. **Recreates, then waits for health.** Traefik cached the old container IPs;
   its service health check is what re-resolves them. Reload before that and
   every request 502s with "no available server".
7. **Rolls back** to the recorded digests if health never arrives.
8. **Smoke tests the public URL** — through DNS, TLS and the gateway, which is
   the path a user takes and the only one that proves the deploy worked.

## When something is wrong

Run the `diagnose production` workflow from the Actions tab. It is read-only
and prints the deploy status, container states, recent logs, health from inside
each container, whether Traefik still resolves its upstreams, published ports,
TLS state, disk and fail2ban bans.

## Rolling back by hand

```bash
gh workflow run deploy-prod.yml -f image_tag=sha-<previous>
```

If the bad release included a non-backward-compatible migration, do not force
old code onto the new schema — restore from backup (`backup-restore.md`).
