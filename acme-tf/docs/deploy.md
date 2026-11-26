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

`.github/workflows/deploy-prod.yml`, run by `workflow_run` when every image
build for a push to `main` has succeeded, or by hand with a tag. A build that
ran for a pull request, a fork, or another branch never deploys.

What it does, and why each step is in that order:

1. **Checks every image exists before touching the box** (`docker manifest
   inspect` on each `sha-<7>` tag). An image the release did not rebuild was
   re-tagged by `retag-unchanged.yml`; one that is missing fails here, with the
   box still on the old release, rather than halfway through a pull.
2. **Joins the tailnet**, then SSHes to a `100.x` address. This is why the
   security group can open 80/443 and nothing else.
3. **Streams `deploy-remote.sh`** from the repo. The script is reviewed like any
   other code and nothing deploy-related is pre-installed on the box, so the box
   cannot drift from the repo.
4. **Refuses `latest`, and any tag outside the Docker tag grammar.** A box
   running `latest` cannot tell you what it is running. With
   `SKIP_IF_ALREADY_DEPLOYED`, a tag already live is a no-op.
5. **Keeps the live compose file as `docker-compose.previous.yml`**, writes the
   new one as `docker-compose.next.yml`, pulls from it, and only then moves it
   into place. A pull that fails leaves the live file untouched.
6. **Migrates before swapping containers.** The old code is still serving, and
   migrations are additive within a release (C-9), so it keeps working against
   the new schema for the seconds in between. Once, here, not in an entrypoint,
   where N starting containers race the lock. It is also the env contract
   check: the migration runs with the new image and the box's env file, so an
   env var the new code requires and the box lacks fails here, before any
   container is replaced.
7. **Recreates, then waits for health.** Traefik cached the old container IPs;
   its service health check is what re-resolves them. Reload before that and
   every request 502s with "no available server".
8. **Rolls back** to `docker-compose.previous.yml`, whose image refs come from
   the running containers' `.Config.Image`, if health never arrives.
9. **Smoke tests the public URL**, through DNS, TLS and the gateway: the path a
   user takes and the only one that proves the deploy worked.

## The deploy user

The SSH key in `PROD_SSH_KEY` is the most powerful secret in the repository:
whoever holds it can run anything the user it belongs to can. Give it a user of
its own rather than the image's default admin user, and restrict it to what a
deploy needs:

- `docker compose` in `/opt/<project>` through a single `sudoers` line, and
  nothing else as root;
- in `authorized_keys`, `restrict` plus `from="100.64.0.0/10"`, so the key works
  only over the tailnet and opens no forwarding;
- no password, and the admin user keeps its own key, held by a person.

The template does not create this user, because the right restriction depends
on the host; `existing-host` in particular may already have one. Until it
exists, treat the key as root on the box.

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
