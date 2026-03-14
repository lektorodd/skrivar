"""Audio recording using sounddevice."""

import io
import threading

import numpy as np
import sounddevice as sd
from scipy.io import wavfile

SAMPLE_RATE = 16000  # 16 kHz — good for speech
CHANNELS = 1  # Mono


class Recorder:
    """Records microphone audio into an in-memory buffer."""

    def __init__(self, sample_rate: int = SAMPLE_RATE, channels: int = CHANNELS):
        self.sample_rate = sample_rate
        self.channels = channels
        self._frames: list[np.ndarray] = []
        self._stream: sd.InputStream | None = None
        self._lock = threading.Lock()
        self._recording = False

    @property
    def is_recording(self) -> bool:
        return self._recording

    def _audio_callback(self, indata: np.ndarray, frames: int, time_info, status):
        """Called by sounddevice for each audio block."""
        if status:
            print(f"[recorder] status: {status}")
        with self._lock:
            self._frames.append(indata.copy())

    def start(self) -> None:
        """Start recording from the default microphone."""
        if self._recording:
            return
        self._frames = []
        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=self.channels,
            dtype="int16",
            callback=self._audio_callback,
        )
        self._stream.start()
        self._recording = True

    def stop(self) -> bytes:
        """Stop recording and return WAV data as bytes."""
        if not self._recording or self._stream is None:
            return b""
        self._stream.stop()
        self._stream.close()
        self._stream = None
        self._recording = False

        with self._lock:
            if not self._frames:
                return b""
            audio_data = np.concatenate(self._frames, axis=0)

        # Write to in-memory WAV file
        buf = io.BytesIO()
        wavfile.write(buf, self.sample_rate, audio_data)
        buf.seek(0)
        return buf.read()
