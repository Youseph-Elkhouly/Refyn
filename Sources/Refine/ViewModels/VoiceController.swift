import Foundation
import Observation

/// Push-to-talk and click-to-record dictation. Transcription is local; nothing is sent anywhere.
@Observable
@MainActor
final class VoiceController {
    enum State: Equatable { case idle, recording, transcribing, failed(String) }

    private(set) var state: State = .idle
    private(set) var levels: [Float] = Array(repeating: 0, count: 28)
    var downloadProgress: Double?
    /// Receives the finished transcript.
    var onTranscript: (String) -> Void = { _ in }

    private let recorder = AudioRecorder()
    private let transcriber = SpeechTranscriber()
    private var startedAt = Date.distantPast

    var isRecording: Bool { state == .recording }
    var isBusy: Bool { state == .recording || state == .transcribing }

    func toggle() { isRecording ? stop() : start() }

    func start() {
        guard !isBusy else { return }
        Task {
            guard await AudioRecorder.requestPermission() else { state = .failed(AudioRecorderError.permissionDenied.localizedDescription); return }
            guard SpeechTranscriber.isDownloaded(Preferences.speechModel) else { state = .failed(TranscriberError.modelNotDownloaded.localizedDescription); return }
            recorder.onLevel = { [weak self] level in
                Task { @MainActor in self?.push(level) }
            }
            do {
                try recorder.start()
                startedAt = .now
                state = .recording
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard state == .recording else { return }
        let samples = recorder.stop()
        levels = Array(repeating: 0, count: levels.count)
        // A tap shorter than a third of a second is an accidental press, not dictation.
        guard Date.now.timeIntervalSince(startedAt) > 0.35 else { state = .idle; return }
        state = .transcribing
        let model = Preferences.speechModel
        Task {
            do {
                let text = try await transcriber.transcribe(samples, model: model)
                state = .idle
                if !text.isEmpty { onTranscript(text) }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func clearError() { if case .failed = state { state = .idle } }

    func download(_ model: SpeechModel) async throws {
        downloadProgress = 0
        defer { downloadProgress = nil }
        _ = try await SpeechTranscriber.download(model) { p in Task { @MainActor [weak self] in self?.downloadProgress = p } }
    }

    private func push(_ level: Float) {
        guard state == .recording else { return }
        levels.removeFirst()
        levels.append(level)
    }
}
