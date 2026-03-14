"""Menubar icon generation using Pillow."""

import os
import tempfile

from PIL import Image, ImageDraw

ICON_SIZE = 22  # macOS menubar standard
_icon_cache: dict[str, str] = {}


def _get_icon_path(name: str) -> str:
    """Get or create a cached icon path."""
    if name in _icon_cache:
        return _icon_cache[name]
    path = os.path.join(tempfile.gettempdir(), f"skrivar_icon_{name}.png")
    _icon_cache[name] = path
    return path


def create_idle_icon() -> str:
    """
    Create a microphone icon for the menubar (idle state).
    Returns the path to the PNG file.
    """
    path = _get_icon_path("idle")
    img = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx = ICON_SIZE // 2
    # Microphone head (rounded rect approximation using ellipse)
    draw.rounded_rectangle(
        [cx - 4, 2, cx + 4, 12],
        radius=4,
        fill=(0, 0, 0, 255),
    )
    # Microphone stand arc
    draw.arc(
        [cx - 6, 6, cx + 6, 18],
        start=0, end=180,
        fill=(0, 0, 0, 255),
        width=2,
    )
    # Microphone stem
    draw.line([cx, 18, cx, 20], fill=(0, 0, 0, 255), width=2)
    # Base
    draw.line([cx - 3, 20, cx + 3, 20], fill=(0, 0, 0, 255), width=2)

    img.save(path, "PNG")
    return path


def create_recording_icon() -> str:
    """
    Create a waveform icon for the menubar (recording state).
    Returns the path to the PNG file.
    """
    path = _get_icon_path("recording")
    img = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx = ICON_SIZE // 2
    cy = ICON_SIZE // 2

    # Waveform bars — 5 bars with varying heights
    bar_heights = [6, 12, 16, 12, 6]
    bar_width = 2
    gap = 2
    total_width = len(bar_heights) * bar_width + (len(bar_heights) - 1) * gap
    start_x = cx - total_width // 2

    for i, h in enumerate(bar_heights):
        x = start_x + i * (bar_width + gap)
        y_top = cy - h // 2
        y_bot = cy + h // 2
        draw.rounded_rectangle(
            [x, y_top, x + bar_width, y_bot],
            radius=1,
            fill=(0, 0, 0, 255),
        )

    img.save(path, "PNG")
    return path
