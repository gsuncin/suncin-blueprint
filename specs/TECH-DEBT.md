# Tech debt

Compromises that are already live. **Nothing here is scheduled** — these are
for the discussion, not the sprint.

Work that has not started belongs in `BACKLOG.md`. A choice we made on purpose
belongs in `DECISIONS.md`.

| ID | Debt | Interest | Trigger to pay |
|---|---|---|---|
| TD-1 | The wire contract between the BFF client and the service routes (header names, status strings) is asserted on both sides separately, never end to end | A rename on one side passes both suites and breaks in production. `make up` plus a manual call is currently the only thing that catches it | A second service, or the first time it bites |
| TD-2 | `docker-compose.yml` (dev) and `acme-tf/modules/app-stack/templates/docker-compose.yml.tftpl` (prod) describe one stack twice | They drift, and dev stops predicting prod | Adding a service, which forces touching both. The render tests assert the invariants that matter (C-12) but not that the two agree |
| TD-3 | Celery worker and beat share one container (`--pool=solo`) | Fine on one box. On two, every scheduled task fires twice | A second app host |
| TD-4 | Nightly backups never leave the box | A volume failure takes the database and its backups together | Before this carries anything you would miss. `acme-tf/docs/backup-restore.md` says where to add the upload |
| TD-5 | The landing bundle is ~324 KB of a 400 KB budget, almost all of it MUI | The budget binds early, and the first real addition will tempt someone to raise it rather than fix it | The first time the budget fails |
