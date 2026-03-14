import AppKit
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "Sound")

/// Plays system sounds for recording lifecycle events.
enum SoundManager {

    /// Sound events in the recording lifecycle.
    enum Event {
        case recordStart     // Recording began
        case recordStop      // Recording stopped
        case transcribeDone  // Transcription completed successfully
        case error           // Something went wrong
    }

    /// Whether sounds are enabled (stored in UserDefaults).
    static var isEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "soundsDisabled") }
        set { UserDefaults.standard.set(!newValue, forKey: "soundsDisabled") }
    }

    /// Play the appropriate sound for an event.
    static func play(_ event: Event) {
        guard isEnabled else { return }

        let soundName: String
        switch event {
        case .recordStart:    soundName = "Tink"
        case .recordStop:     soundName = "Pop"
        case .transcribeDone: soundName = "Glass"
        case .error:          soundName = "Basso"
        }

        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.play()
        } else {
            logger.warning("Sound '\(soundName)' not found")
        }
    }
}
