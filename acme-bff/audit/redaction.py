"""Redact before writing, never after.

A cleanup pass that runs later is a cleanup pass that can fail, and until it
runs the secret is in the table and in every backup taken meanwhile.
"""

import re
from typing import Any

SENSITIVE_KEYS = {
    "access_token",
    "api_key",
    "apikey",
    "authorization",
    "client_secret",
    "credential",
    "password",
    "private_key",
    "refresh_token",
    "secret",
    "token",
}

REDACTED = "[REDACTED]"

# Providers echo credentials back inside free-text error messages, where no
# key-based rule can see them.
_PATTERNS = [
    re.compile(r"(Bearer\s+)[A-Za-z0-9._\-]+", re.IGNORECASE),
    re.compile(r"((?:api[_-]?key|token|secret|password)[\"':=\s]+)[^\s,;\"'}]+", re.IGNORECASE),
]


def redact_payload(payload: Any) -> Any:
    if isinstance(payload, dict):
        return {
            key: REDACTED if str(key).lower() in SENSITIVE_KEYS else redact_payload(value)
            for key, value in payload.items()
        }
    if isinstance(payload, list):
        return [redact_payload(item) for item in payload]
    if isinstance(payload, str):
        return redact_text(payload)
    return payload


def redact_text(text: str) -> str:
    if not text:
        return text
    for pattern in _PATTERNS:
        text = pattern.sub(rf"\1{REDACTED}", text)
    return text
