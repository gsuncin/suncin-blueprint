import json

# Recycle workers to bound the damage from a slow leak, and jitter so they do
# not all recycle in lockstep and drop throughput to zero for a moment.
max_requests = 500
max_requests_jitter = 50
timeout = 60

# Gunicorn installs its own log config, which would emit plain text alongside
# the application's JSON and break any parser reading the stream.
logconfig_dict = json.loads(
    json.dumps(
        {
            "version": 1,
            "disable_existing_loggers": False,
            "formatters": {"json": {"()": "core.logging.JsonFormatter"}},
            "handlers": {
                "console": {"class": "logging.StreamHandler", "formatter": "json"}
            },
            "root": {"handlers": ["console"], "level": "INFO"},
            "loggers": {
                "gunicorn.error": {"handlers": ["console"], "level": "INFO", "propagate": False},
                "gunicorn.access": {"handlers": ["console"], "level": "INFO", "propagate": False},
            },
        }
    )
)
