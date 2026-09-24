# GitHub Actions secrets

The template for every key CI needs. A repository secret cannot have a
committed `.example` file the way `.env` does, so this manifest **is** the
template: nothing may be referenced from a workflow without a row here saying
what it is, who issues it, and how to rotate it.

Never paste a value into this file, an issue, a PR, or a chat.

## Required — `environment: production`

| Secret | What it is | How to obtain / rotate |
|---|---|---|
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client, so the runner can join the tailnet | Tailscale admin → Settings → OAuth clients, scope `auth_keys`, tag `tag:ci`. Rotate by issuing a new client and deleting the old |
| `TS_OAUTH_SECRET` | The matching secret | Shown once at creation. If it is ever seen outside the secret store, issue a new client |
| `PROD_SSH_KEY` | Private half of the deploy key, PEM, whole file including headers | `ssh-keygen -t ed25519 -C acme-deploy -f deploy_key`. The **public** half goes in `terraform.tfvars` and the bootstrap script; the private half only ever goes here |
| `PROD_SSH_HOST` | The box's tailnet address (`100.x.y.z`) or MagicDNS name | Tailscale admin. **Not** the public IP — CI never SSHes over the internet |
| `PROD_SSH_USER` | `deploy` | Created by the bootstrap script. Never `root` |
| `PROD_DOMAIN_APP` | Public hostname the smoke test hits, e.g. `app.example.com` | Matches the DNS record for the app |

`GITHUB_TOKEN` is injected by Actions and is what authenticates the pull from
`ghcr.io`. It is not configured here.

## The manifest cannot fall behind the workflows

`.github/scripts/check-deploy-contract.sh` section 5 derives every `secrets.*`
a workflow reads and fails if this table has no row for one. It strips comments
first, which is load-bearing in both directions:

- A workflow **reading** a secret with no row here is a deploy that fails at
  run time — in production, on a release.
- A **comment** mentioning a secret that was deliberately removed must not
  demand a row. `bff-tests.yml` explains that `CI_JWT_PRIVATE_KEY_B64` was
  taken out and the key is now generated in the step; requiring a row for a
  secret nothing reads is the opposite failure.

## Secrets this repo deliberately does NOT have

Worth writing down, because the instinct on seeing a missing value is to add
one:

- **`CI_JWT_PRIVATE_KEY_B64`** — `bff-tests.yml` generates a throwaway RSA key
  inside the `check --deploy` step. That command starts the process and signs
  nothing, so a real key would be a secret published for no benefit.
- **`STORAGE_*` for CI** — same bargain. The step needs the composition root's
  required-setting refusal to be reachable, not a real object store.

## When `deploy production` is red because of this file

`tailscale/github-action` exits at its "Check Auth Info Empty" step and the job
fails **in about 11 seconds**, before any deploy code runs:

```
##[error]OAuth identity empty, Maybe you need to populate it in the Secrets
         for your workflow
```

That is a missing prerequisite, not a deploy failure. Read it as "rows above
are unset", not as "the deploy is broken".
