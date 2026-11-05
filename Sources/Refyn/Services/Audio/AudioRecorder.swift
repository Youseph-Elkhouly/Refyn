import AVFoundation

enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied, noInput, converterUnavailable
    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Microphone access is off. Allow Refyn in System Settings › Privacy & Security › Microphone."
        case .noInput: "No microphone is available."
        case .converterUnavailable: "Could not prepare audio for transcription."
        }
    }
}

/// Records the microphone as 16 kHz mono floats (what Whisper expects) and reports input levels.
/// Recording only ever starts from an explicit user action.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    /// Called on the audio thread with a 0…1 level per buffer.
    var onLevel: (@Sendable (Float) -> Void)?

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioRecorderError.noInput }
        guard let converter = AVAudioConverter(from: format, to: target) else { throw AudioRecorderError.converterUnavailable }
        self.converter = converter
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in self?.process(buffer) }
        engine.prepare()
        try engine.start()
    }

    /// Stops and returns everything recorded since `start()`.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock { let out = samples; samples.removeAll(); return out }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        if let channel = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += channel[i] * channel[i] }
            let rms = (sum / Float(max(buffer.frameLength, 1))).squareRoot()
            onLevel?(min(1, rms * 12))
        }
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
        lock.withLock { samples.append(contentsOf: chunk) }
    }
}
