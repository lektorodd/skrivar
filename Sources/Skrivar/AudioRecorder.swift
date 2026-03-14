import AVFoundation
import CoreAudio
import Foundation
import os.log

private let logger = Logger(subsystem: "com.skrivar.app", category: "AudioRecorder")

/// Represents an available audio input device.
struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String

    static func == (lhs: AudioInputDevice, rhs: AudioInputDevice) -> Bool {
        lhs.uid == rhs.uid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
}

/// Records microphone audio using AVAudioEngine, outputs WAV bytes.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioData = Data()
    private let sampleRate: Double = 16000
    private let lock = NSLock()
    private(set) var isRecording = false

    /// Callback for real-time audio level (0.0 – 1.0), fired on audio thread.
    var onAudioLevel: ((Float) -> Void)?

    // MARK: - Device Enumeration

    /// List all available audio input devices.
    static func availableInputDevices() -> [AudioInputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { deviceID -> AudioInputDevice? in
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize) == noErr,
                  inputSize > 0 else { return nil }

            let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPtr.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &inputSize, bufferListPtr) == noErr else {
                return nil
            }

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { return nil }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameRef: CFString = "" as CFString
            guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef) == noErr else {
                return nil
            }

            // Get device UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            var uidRef: CFString = "" as CFString
            guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uidRef) == noErr else {
                return nil
            }

            return AudioInputDevice(
                id: deviceID,
                uid: uidRef as String,
                name: nameRef as String
            )
        }
    }

    /// Set the audio input device by UID. Pass nil for system default.
    func setInputDevice(uid: String?) {
        guard let uid, !uid.isEmpty else {
            // Reset to system default — AVAudioEngine uses default automatically
            logger.info("Using system default audio input")
            return
        }

        let devices = Self.availableInputDevices()
        guard let device = devices.first(where: { $0.uid == uid }) else {
            logger.warning("Audio device with UID '\(uid)' not found, using default")
            return
        }

        // Set the device on the audio engine's input node
        var deviceID = device.id
        let status = AudioUnitSetProperty(
            engine.inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status == noErr {
            logger.info("Audio input set to: \(device.name)")
        } else {
            logger.error("Failed to set audio input device: \(status)")
        }
    }

    /// Pre-warm: request mic permission early so the engine is ready on first recording.
    func prewarm() {
        // Don't call engine.prepare() here — it crashes if audio nodes
        // aren't available yet (e.g. first launch of bundled .app).
        // The engine will prepare implicitly when start() is called.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                logger.info("Mic permission \(granted ? "granted" : "denied")")
            }
        }
        logger.info("Audio recorder ready")
    }

    /// Start recording from the configured microphone.
    func start() throws {
        guard !isRecording else { return }

        // Apply saved device preference
        let savedUID = UserDefaults.standard.string(forKey: "audioInputDeviceUID")
        setInputDevice(uid: savedUID)

        audioData = Data()
        audioData.reserveCapacity(16000 * 2 * 10) // Reserve ~10s at 16kHz 16-bit
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

            // Compute RMS audio level for waveform visualization
            if let levelCallback = self.onAudioLevel,
               let floatData = buffer.floatChannelData {
                let channelData = floatData[0]
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameLength {
                    let sample = channelData[i]
                    sum += sample * sample
                }
                let rms = sqrtf(sum / Float(max(frameLength, 1)))
                let level = min(rms * 4.0, 1.0) // Scale up for visibility
                levelCallback(level)
            }

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
        wav.reserveCapacity(44 + pcmData.count)
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

