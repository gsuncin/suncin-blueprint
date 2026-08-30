"""Fernet helpers, made per secret domain rather than shared.

Two secret domains that share a key are one leak away from being one domain.
The factory keeps the code in one place while keeping the keys separate — you
call it once per domain with that domain's setting name.
"""

from collections.abc import Callable

from cryptography.fernet import Fernet, InvalidToken
from django.conf import settings


class EncryptionError(Exception):
    """Encrypting or decrypting failed. Carries no plaintext and no key."""


def make_fernet_helpers(
    setting_name: str, error_class: type[Exception] = EncryptionError
) -> tuple[Callable[[str], str], Callable[[str], str]]:
    """Return (encrypt_text, decrypt_text) bound to one settings key."""

    def _fernet() -> Fernet:
        key = getattr(settings, setting_name, "")
        if not key:
            raise error_class(f"{setting_name} is not configured")
        try:
            return Fernet(key.encode() if isinstance(key, str) else key)
        except (ValueError, TypeError) as exc:
            # The message names the setting, never the value.
            raise error_class(f"{setting_name} is not a valid Fernet key") from exc

    def encrypt_text(plaintext: str) -> str:
        return _fernet().encrypt(plaintext.encode()).decode()

    def decrypt_text(ciphertext: str) -> str:
        try:
            return _fernet().decrypt(ciphertext.encode()).decode()
        except InvalidToken as exc:
            raise error_class(
                f"Could not decrypt with {setting_name}; wrong key or corrupt value"
            ) from exc

    return encrypt_text, decrypt_text


encrypt_provider_credential, decrypt_provider_credential = make_fernet_helpers(
    "PROVIDER_CREDENTIAL_ENCRYPTION_KEY"
)
