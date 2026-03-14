"""Dynamic Island–style floating pill overlay using PyObjC/AppKit."""

import threading
import time

import objc
from AppKit import (
    NSApplication,
    NSBackingStoreBuffered,
    NSBezierPath,
    NSColor,
    NSFont,
    NSMakeRect,
    NSScreen,
    NSView,
    NSWindow,
    NSWindowCollectionBehaviorCanJoinAllSpaces,
    NSWindowCollectionBehaviorStationary,
)
from Foundation import NSObject, NSTimer, NSRunLoop, NSDefaultRunLoopMode
from Quartz import CGWindowLevelForKey, kCGStatusWindowLevelKey

# Overlay dimensions
PILL_WIDTH = 180
PILL_HEIGHT = 36
PILL_CORNER_RADIUS = 18
DOT_RADIUS = 4
DOT_SPACING = 16
NUM_DOTS = 3


class PulsingDotsView(NSView):
    """Custom NSView that draws animated pulsing dots."""

    def initWithFrame_(self, frame):
        self = objc.super(PulsingDotsView, self).initWithFrame_(frame)
        if self is None:
            return None
        self._phase = 0.0
        return self

    def setPhase_(self, phase):
        self._phase = phase
        self.setNeedsDisplay_(True)

    def drawRect_(self, rect):
        # Clear background with dark pill shape
        NSColor.clearColor().set()
        path = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
            self.bounds(), PILL_CORNER_RADIUS, PILL_CORNER_RADIUS
        )

        # Dark semi-transparent background
        NSColor.colorWithCalibratedRed_green_blue_alpha_(0.08, 0.08, 0.1, 0.92).set()
        path.fill()

        # Subtle border
        NSColor.colorWithCalibratedRed_green_blue_alpha_(0.3, 0.3, 0.35, 0.5).set()
        path.setLineWidth_(0.5)
        path.stroke()

        # Draw pulsing dots
        cx = self.bounds().size.width / 2
        cy = self.bounds().size.height / 2
        total_width = (NUM_DOTS - 1) * DOT_SPACING
        start_x = cx - total_width / 2

        for i in range(NUM_DOTS):
            # Each dot pulses with a phase offset
            import math
            phase_offset = i * (2.0 * math.pi / NUM_DOTS)
            pulse = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(self._phase + phase_offset))
            radius = DOT_RADIUS * (0.7 + 0.3 * pulse)

            # Color: white with pulsing alpha
            NSColor.colorWithCalibratedRed_green_blue_alpha_(
                1.0, 1.0, 1.0, pulse
            ).set()

            dot_x = start_x + i * DOT_SPACING
            dot_rect = NSMakeRect(
                dot_x - radius, cy - radius,
                radius * 2, radius * 2,
            )
            dot_path = NSBezierPath.bezierPathWithOvalInRect_(dot_rect)
            dot_path.fill()


class AnimationDelegate(NSObject):
    """Drives the pulsing animation via NSTimer."""

    def initWithView_(self, view):
        self = objc.super(AnimationDelegate, self).init()
        if self is None:
            return None
        self._view = view
        self._start_time = time.time()
        self._timer = None
        return self

    def start(self):
        self._start_time = time.time()
        self._timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            1.0 / 30.0,  # ~30 FPS
            self,
            "tick:",
            None,
            True,
        )
        NSRunLoop.currentRunLoop().addTimer_forMode_(self._timer, NSDefaultRunLoopMode)

    def stop(self):
        if self._timer:
            self._timer.invalidate()
            self._timer = None

    def tick_(self, timer):
        import math
        elapsed = time.time() - self._start_time
        phase = elapsed * 3.0  # Speed of pulsing
        self._view.setPhase_(phase)


class Overlay:
    """Manages the Dynamic Island–style overlay window."""

    def __init__(self):
        self._window = None
        self._dots_view = None
        self._animator = None
        self._visible = False

    def _ensure_window(self):
        """Create the overlay window if it doesn't exist."""
        if self._window is not None:
            return

        # Get main screen dimensions
        screen = NSScreen.mainScreen()
        screen_frame = screen.frame()

        # Position: centered horizontally, near top of screen
        x = (screen_frame.size.width - PILL_WIDTH) / 2
        y = screen_frame.size.height - PILL_HEIGHT - 12  # 12px from top

        frame = NSMakeRect(x, y, PILL_WIDTH, PILL_HEIGHT)

        self._window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            frame,
            0,  # NSBorderlessWindowMask
            NSBackingStoreBuffered,
            False,
        )
        self._window.setLevel_(CGWindowLevelForKey(kCGStatusWindowLevelKey) + 1)
        self._window.setOpaque_(False)
        self._window.setBackgroundColor_(NSColor.clearColor())
        self._window.setHasShadow_(True)
        self._window.setIgnoresMouseEvents_(True)
        self._window.setCollectionBehavior_(
            NSWindowCollectionBehaviorCanJoinAllSpaces
            | NSWindowCollectionBehaviorStationary
        )

        # Create the pulsing dots view
        content_frame = NSMakeRect(0, 0, PILL_WIDTH, PILL_HEIGHT)
        self._dots_view = PulsingDotsView.alloc().initWithFrame_(content_frame)
        self._window.contentView().addSubview_(self._dots_view)

        # Create animator
        self._animator = AnimationDelegate.alloc().initWithView_(self._dots_view)

    def show(self):
        """Show the overlay (must be called on main thread)."""
        if self._visible:
            return

        self._ensure_window()
        self._window.orderFrontRegardless()
        self._animator.start()
        self._visible = True

    def hide(self):
        """Hide the overlay (must be called on main thread)."""
        if not self._visible:
            return

        if self._animator:
            self._animator.stop()
        if self._window:
            self._window.orderOut_(None)
        self._visible = False

    @property
    def is_visible(self) -> bool:
        return self._visible
