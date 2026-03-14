import AVFoundation
import Foundation

/// Records microphone audio using AVAudioEngine, outputs WAV bytes.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioData = Data()
    private let sampleRate: Double = 16000
    private let lock = NSLock()
    private(set) var isRecording = false

    /// Start recording from the default microphone.
    func start() throws {
        guard !isRecording else { return }

        audioData = Data()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        // Target format: 16kHz, mono, 16-bit PCM
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw RecorderError.formatError
        }

        // Create converter from input format to target format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterError
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self else { return }

            // Convert to target format
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate
            )
            guard frameCapacity > 0,
                  let convertedBuffer = AVAudioPCMBuffer(
                      pcmFormat: targetFormat, frameCapacity: frameCapacity
                  )
            else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else { return }

            // Append raw PCM data
            if let channelData = convertedBuffer.int16ChannelData {
                let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
                let data = Data(bytes: channelData[0], count: byteCount)
                self.lock.lock()
                self.audioData.append(data)
                self.lock.unlock()
            }
        }

        try engine.start()
        isRecording = true
    }

    /// Stop recording and return WAV file data.
    func stop() -> Data {
        guard isRecording else { return Data() }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        lock.lock()
        let pcmData = audioData
        audioData = Data()
        lock.unlock()

        guard !pcmData.isEmpty else { return Data() }
        return createWAV(from: pcmData)
    }

    /// Create a WAV file from raw PCM data.
    private func createWAV(from pcmData: Data) -> Data {
        var wav = Data()
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleRateInt = UInt32(sampleRate)
        let byteRate = sampleRateInt * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        wav.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        wav.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: sampleRateInt.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        wav.append(contentsOf: "data".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        wav.append(pcmData)

        return wav
    }

    enum RecorderError: Error {
        case formatError
        case converterError
    }
}
