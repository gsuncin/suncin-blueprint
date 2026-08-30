import json
import logging
from datetime import datetime, timezone

SCHEMA = "acme.log.v1"


class JsonFormatter(logging.Formatter):
    """One JSON object per line, with a versioned schema.

    The schema field is what lets a log pipeline keep parsing old lines after
    the shape changes. Without it, every field rename silently breaks whatever
    was built on top of the logs.
    """

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "schema": SCHEMA,
            "service": "acme-bff",
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        for field in ("event", "account_id", "correlation_id", "request_id"):
            value = getattr(record, field, None)
            if value is not None:
                payload[field] = value

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        return json.dumps(payload, default=str)
