"""Last line of defence before anything leaves for Sentry (C-3)."""

from typing import Any

SENSITIVE_KEYS = {
    "authorization",
    "api_key",
    "apikey",
    "credential",
    "password",
    "refresh_token",
    "access_token",
    "secret",
    "token",
    "x-provider-credential",
}

REDACTED = "[REDACTED]"


def scrub_event(event: dict[str, Any], hint: dict[str, Any]) -> dict[str, Any]:
    """Drop identifying and secret material from an event before it is sent.

    Only the user id and account id survive on `user` — an email address in a
    breadcrumb is a personal-data export to a third party that nobody consented
    to, and it is never the field that helps you debug.
    """
    user = event.get("user")
    if isinstance(user, dict):
        event["user"] = {
            key: user[key] for key in ("id", "account_id") if key in user
        }

    return _scrub(event)


def _scrub(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            key: REDACTED if str(key).lower() in SENSITIVE_KEYS else _scrub(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [_scrub(item) for item in value]
    return value
