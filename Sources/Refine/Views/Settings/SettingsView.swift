import RefineCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    let onShortcutsChanged: () -> Void

    var body: some View {
        TabView {
            ModelSettings(model: model).tabItem { Label("Model", systemImage: "sparkles") }
            ShortcutSettings(onChange: onShortcutsChanged).tabItem { Label("Shortcuts", systemImage: "keyboard") }
            VoiceSettings(voice: model.voice).tabItem { Label("Voice", systemImage: "mic") }
            AnalysisSettings(model: model).tabItem { Label("Analysis", systemImage: "point.3.connected.trianglepath.dotted") }
        }
        .padding(20)
        .frame(width: 560, height: 520)
    }
}

struct ModelSettings: View {
    let model: AppModel
    @State private var apiKey = ""
    @State private var hasKey = Preferences.keychain.read(Preferences.geminiAccount) != nil
    @State private var modelName = Preferences.geminiModel
    @State private var iterations = Preferences.iterationLimit
    @State private var status: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section("Gemini") {
                SecureField(hasKey ? "Stored in Keychain — enter a new key to replace" : "API key", text: $apiKey)
                HStack {
                    Button("Save Key") {
                        do { try Preferences.keychain.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Preferences.geminiAccount); apiKey = ""; hasKey = true; status = "Saved to Keychain." }
                        catch { status = error.localizedDescription }
                    }.disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Remove Key") { try? Preferences.keychain.delete(Preferences.geminiAccount); hasKey = false; status = "Removed." }.disabled(!hasKey)
                    Button("Test") { Task { await test() } }.disabled(!hasKey || testing)
                    if testing { ProgressView().controlSize(.small) }
                }
                TextField("Model", text: $modelName).onSubmit { Preferences.geminiModel = modelName }
                    .onChange(of: modelName) { Preferences.geminiModel = modelName }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                Text("Only your request and a small, relevant slice of workspace context (component names, paths, symbols, notes you marked) are sent. Source files are never uploaded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Prompts") {
                Stepper("Fix-loop attempts: \(iterations)", value: $iterations, in: 1...10).onChange(of: iterations) { Preferences.iterationLimit = iterations }
            }
        }
        .formStyle(.grouped)
    }

    func test() async {
        testing = true
        defer { testing = false }
        guard let key = Preferences.keychain.read(Preferences.geminiAccount) else { return }
        do {
            let plan = try await GeminiProvider(apiKey: key, model: Preferences.geminiModel).plan(for: OptimizationRequest(
                analysis: RequestAnalysis("Add a health check endpoint"), mode: .basic, techniques: [.structured],
                context: RetrievedContext(workspaceName: "test", languages: [], frameworks: [], components: [], notes: [], recentChanges: [], analyzed: false), iterationLimit: 0))
            status = "Working: \(Preferences.geminiModel) returned a valid plan (\(plan.tasks.count) tasks)."
        } catch { status = error.localizedDescription }
    }
}

struct ShortcutSettings: View {
    let onChange: () -> Void
    @State private var toggle = Preferences.toggleShortcut
    @State private var talk = Preferences.pushToTalkShortcut
    @State private var collapse = Preferences.collapseOnFocusLoss

    var body: some View {
        Form {
            Section("Global shortcuts") {
                LabeledContent("Open / collapse Refine") { ShortcutRecorder(shortcut: $toggle) }
                LabeledContent("Hold to dictate") { ShortcutRecorder(shortcut: $talk) }
                Text("Shortcuts work in every app and need no Accessibility permission.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Panel") {
                Toggle("Collapse when I switch to another app", isOn: $collapse)
            }
        }
        .formStyle(.grouped)
        .onChange(of: toggle) { Preferences.toggleShortcut = toggle; onChange() }
        .onChange(of: talk) { Preferences.pushToTalkShortcut = talk; onChange() }
        .onChange(of: collapse) { Preferences.collapseOnFocusLoss = collapse }
    }
}

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys…" : shortcut.display) { recording ? stop() : start() }
            .frame(minWidth: 120)
            .onDisappear(perform: stop)
    }

    func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Escape cancels
            if let s = Shortcut(event: event) { shortcut = s; stop() }
            return nil
        }
    }

    func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

struct VoiceSettings: View {
    let voice: VoiceController
    @State private var mode = Preferences.voiceMode
    @State private var speechModel = Preferences.speechModel
    @State private var downloaded: Set<SpeechModel> = Set(SpeechModel.allCases.filter(SpeechTranscriber.isDownloaded))
    @State private var error: String?

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Mode", selection: $mode) { ForEach(VoiceMode.allCases) { Text($0.rawValue).tag($0) } }
                Text(mode.summary).font(.caption).foregroundStyle(.secondary)
                Text("Recording starts only when you press the shortcut or the microphone button. Speech is transcribed on this Mac and never sent to a model automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Speech model (WhisperKit, on-device)") {
                Picker("Model", selection: $speechModel) {
                    ForEach(SpeechModel.allCases) { m in Text(m.label + (downloaded.contains(m) ? " ✓" : "")).tag(m) }
                }
                HStack {
                    if let p = voice.downloadProgress {
                        ProgressView(value: p).frame(width: 200)
                        Text("\(Int(p * 100))%")
                    } else if downloaded.contains(speechModel) {
                        Label("Downloaded", systemImage: "checkmark.circle").foregroundStyle(.green)
                    } else {
                        Button("Download") {
                            Task {
                                do { try await voice.download(speechModel); downloaded.insert(speechModel); error = nil }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .onChange(of: mode) { Preferences.voiceMode = mode }
        .onChange(of: speechModel) { Preferences.speechModel = speechModel }
    }
}

struct AnalysisSettings: View {
    let model: AppModel
    @State private var nodePath = Preferences.nodePath
    @State private var status = "Checking…"

    var body: some View {
        Form {
            Section("Node.js helper") {
                TextField("Node.js path (blank = auto-detect)", text: $nodePath)
                HStack {
                    Button("Apply & Check") { Task { Preferences.nodePath = nodePath; await model.restartHelper(); await check() } }
                    Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text("The helper parses code, reads git and renders diagrams with Giotto. It runs only while needed and never executes repository code.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Coverage") {
                Text("TypeScript and JavaScript are parsed with the TypeScript compiler. Python, Swift and Prisma use pattern-based extraction. Other languages are counted but not analyzed. Secrets (.env, keys, credentials), dependencies and build output are always excluded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await check() }
    }

    func check() async {
        do {
            let node = try HelperClient.locateNode(override: Preferences.nodePath.isEmpty ? nil : Preferences.nodePath)
            let script = try HelperClient.locateHelperScript()
            status = "Node: \(node)\nHelper: \(script.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path)"
        } catch { status = error.localizedDescription }
    }
}
