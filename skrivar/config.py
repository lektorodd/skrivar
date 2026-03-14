"""API key and settings management via macOS Keychain."""

import json
import keyring

SERVICE_NAME = "skrivar-stt"
ACCOUNT_API_KEY = "elevenlabs_api_key"
ACCOUNT_SETTINGS = "settings"

DEFAULT_SETTINGS = {
    "language_code": "nor",  # ISO 639-3 code; empty string = auto-detect
}


def get_api_key() -> str | None:
    """Retrieve the ElevenLabs API key from macOS Keychain."""
    return keyring.get_password(SERVICE_NAME, ACCOUNT_API_KEY)


def set_api_key(key: str) -> None:
    """Store the ElevenLabs API key in macOS Keychain."""
    keyring.set_password(SERVICE_NAME, ACCOUNT_API_KEY, key)


def has_api_key() -> bool:
    """Check if an API key is configured."""
    key = get_api_key()
    return key is not None and len(key.strip()) > 0


def get_settings() -> dict:
    """Retrieve app settings from Keychain."""
    raw = keyring.get_password(SERVICE_NAME, ACCOUNT_SETTINGS)
    if raw:
        try:
            saved = json.loads(raw)
            # Merge with defaults so new keys are always present
            return {**DEFAULT_SETTINGS, **saved}
        except json.JSONDecodeError:
            pass
    return dict(DEFAULT_SETTINGS)


def set_settings(settings: dict) -> None:
    """Store app settings in Keychain."""
    keyring.set_password(SERVICE_NAME, ACCOUNT_SETTINGS, json.dumps(settings))


def get_language_code() -> str:
    """Get the configured language code for transcription."""
    return get_settings().get("language_code", "nor")


def set_language_code(code: str) -> None:
    """Set the language code for transcription."""
    settings = get_settings()
    settings["language_code"] = code
    set_settings(settings)
