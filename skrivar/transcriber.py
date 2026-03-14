"""ElevenLabs Scribe v2 transcription."""

import io

from elevenlabs import ElevenLabs


def transcribe(wav_bytes: bytes, api_key: str, language_code: str = "") -> str:
    """
    Send WAV audio to ElevenLabs Scribe v2 and return the transcribed text.

    Args:
        wav_bytes: Raw WAV file bytes.
        api_key: ElevenLabs API key.
        language_code: ISO 639-1/3 language hint (e.g. "nor", "eng").
                       Empty string means auto-detect.

    Returns:
        The transcribed text, or an error message string.
    """
    if not wav_bytes:
        return ""

    try:
        client = ElevenLabs(api_key=api_key)
        audio_file = io.BytesIO(wav_bytes)
        audio_file.name = "recording.wav"  # ElevenLabs needs a filename

        kwargs = {
            "file": audio_file,
            "model_id": "scribe_v2",
        }
        if language_code:
            kwargs["language_code"] = language_code

        result = client.speech_to_text.convert(**kwargs)
        return result.text.strip() if result.text else ""

    except Exception as e:
        print(f"[transcriber] Error: {e}")
        return f"[Transcription error: {e}]"
