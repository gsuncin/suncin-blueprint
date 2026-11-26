# Backup and restore

## What runs

`acme-backup.timer` fires nightly at 02:31 with up to 15 minutes of jitter, and
runs `/usr/local/bin/acme-backup.sh`:

- `pg_dump -Fc` into `/var/backups/acme/postgres/`
- a `.sha256` beside each dump
- deletes dumps older than `backup_retention_days` (default 14)

```bash
systemctl list-timers acme-backup.timer
journalctl -u acme-backup.service --since '2 days ago'
ls -lh /var/backups/acme/postgres/
```

## The part that is not done for you

**Unless `backup_upload_url` is set, these backups do not leave the box.** A
volume that fails takes the database and its backups together. Set
`backup_upload_url` on the module to a write-only, pre-authenticated object
storage prefix (an OCI pre-authenticated request, or an S3 presigned prefix),
ending in `/`, and each dump and its `.sha256` are PUT there after they are
written. A failed upload fails `acme-backup.service`; put an alert on that unit.
Give the bucket a lifecycle rule, since the box only prunes its own copies.

**And a backup nobody has restored is a hope.** The checksum catches a
truncated write; it says nothing about whether the dump is usable. Restore into
a scratch database on a schedule you actually keep.

## Restoring

```bash
# 1. Verify the dump first.
cd /var/backups/acme/postgres
sha256sum -c acme-20260829T023100Z.dump.sha256

# 2. Stop everything that writes. The worker included — a beat schedule firing
#    mid-restore will write into a half-restored database.
cd /opt/acme
sudo docker compose stop bff worker

# 3. Restore into a NEW database, not over the live one. If the dump turns out
#    to be bad you still have the original to compare against.
sudo docker compose exec -T postgres createdb -U acme acme_restored
sudo docker compose exec -T postgres pg_restore -U acme -d acme_restored --no-owner \
    < acme-20260829T023100Z.dump

# 4. Look at it before you commit to it.
sudo docker compose exec -T postgres psql -U acme -d acme_restored \
    -c "select count(*) from example_examplerecord;"

# 5. Swap, keeping the old one.
sudo docker compose exec -T postgres psql -U acme -d postgres -c \
    "alter database acme rename to acme_before_restore;"
sudo docker compose exec -T postgres psql -U acme -d postgres -c \
    "alter database acme_restored rename to acme;"

sudo docker compose start bff worker
curl -sS https://app.example.com/api/health
```

Keep `acme_before_restore` until you are certain. Dropping it is a separate,
deliberate step.
