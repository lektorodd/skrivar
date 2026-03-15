import Foundation
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "AudioCompressor")

/// Compresses raw PCM WAV data to AAC using macOS built-in `afconvert`.
enum AudioCompressor {

    /// Threshold: only compress recordings longer than this (in bytes).
    /// At 16kHz mono 16-bit = 32000 bytes/second, ~30 seconds ≈ 960KB.
    /// Short/medium recordings upload fast as WAV; only long ones benefit from compression.
    static let compressionThreshold = 960_000

    /// Result of compression: data + metadata for the Transcriber.
    struct CompressedAudio {
        let data: Data
        let filename: String
        let mimeType: String
    }

    /// Compress WAV data to AAC if it exceeds the threshold.
    /// Returns the original WAV if compression fails or data is too small.
    static func compressIfNeeded(wavData: Data) -> CompressedAudio {
        guard wavData.count > compressionThreshold else {
            return CompressedAudio(data: wavData, filename: "recording.wav", mimeType: "audio/wav")
        }

        if let aacData = compressToAAC(wavData: wavData) {
            let ratio = Double(wavData.count) / Double(max(aacData.count, 1))
            logger.info("Compressed \(wavData.count) → \(aacData.count) bytes (\(String(format: "%.1f", ratio))x)")
            return CompressedAudio(data: aacData, filename: "recording.m4a", mimeType: "audio/mp4")
        }

        logger.warning("AAC compression failed, falling back to WAV")
        return CompressedAudio(data: wavData, filename: "recording.wav", mimeType: "audio/wav")
    }

    /// Convert WAV data to AAC using macOS built-in `afconvert` command.
    private static func compressToAAC(wavData: Data) -> Data? {
        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")
        let m4aURL = tempDir.appendingPathComponent(UUID().uuidString + ".m4a")

        defer {
            try? FileManager.default.removeItem(at: wavURL)
            try? FileManager.default.removeItem(at: m4aURL)
        }

        do {
            try wavData.write(to: wavURL)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            process.arguments = [
                wavURL.path,
                m4aURL.path,
                "-d", "aac",     // AAC codec
                "-f", "m4af",    // M4A container
                "-b", "64000",   // 64kbps bitrate (good for speech)
                "-q", "127",     // Highest quality
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                logger.error("afconvert exited with status \(process.terminationStatus)")
                return nil
            }

            return try Data(contentsOf: m4aURL)
        } catch {
            logger.error("Compression failed: \(error.localizedDescription)")
            return nil
        }
    }
}
