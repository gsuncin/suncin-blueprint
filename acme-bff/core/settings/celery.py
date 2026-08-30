from celery.schedules import crontab
from core.settings.env import config

CELERY_BROKER_URL = config("CELERY_BROKER_URL", default="amqp://guest:guest@localhost:5672//")
# No result backend: every task here is a side effect, and storing results we
# never read means a growing table nobody prunes.
CELERY_TASK_IGNORE_RESULT = True
CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True
CELERY_TASK_ALWAYS_EAGER = config("CELERY_TASK_ALWAYS_EAGER", default=False, cast=bool)
CELERY_TIMEZONE = config("TIME_ZONE", default="UTC")

CELERY_BEAT_SCHEDULE = {
    # The safety net for verdicts that never arrived. Providers lose webhooks;
    # a sweep is the only thing that notices (C-4).
    "sweep-example-jobs": {
        "task": "example.sweep_example_jobs_task",
        "schedule": crontab(minute="*/15"),
    },
    "prune-audit-payloads": {
        "task": "audit.prune_audit_payloads_task",
        "schedule": crontab(hour=3, minute=20),
    },
}
