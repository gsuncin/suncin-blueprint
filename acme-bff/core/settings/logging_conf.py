from core.settings.env import config

LOG_LEVEL = config("LOG_LEVEL", default="INFO")

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {"()": "core.logging.JsonFormatter"},
    },
    "handlers": {
        "console": {"class": "logging.StreamHandler", "formatter": "json"},
    },
    "root": {"handlers": ["console"], "level": LOG_LEVEL},
    "loggers": {
        # Django logs every 4xx at WARNING with the full path, which on a
        # public box is mostly scanner noise the gateway already blocked.
        "django.request": {"handlers": ["console"], "level": "ERROR", "propagate": False},
    },
}
