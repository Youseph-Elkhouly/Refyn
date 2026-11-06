import RefineCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    let onShortcutsChanged: () -> Void
    enum Tab: String, CaseIterable { case model = "Model", shortcuts = "Shortcuts", voice = "Voice", workspace = "Workspace" }
    @State private var tab: Tab = .model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Segmented(options: Tab.allCases, selection: $tab) { $0.rawValue }
                Spacer()
            }
            .padding(.horizontal, Theme.Space.xl).padding(.top, 44).padding(.bottom, Theme.Space.md)
            Hairline()
            ScrollView {
                Group {
                    switch tab {
                    case .model: ModelSettings(model: model)
                    case .shortcuts: ShortcutSettings(onChange: onShortcutsChanged)
                    case .voice: VoiceSettings(voice: model.voice)
                    case .workspace: AnalysisSettings(model: model)
                    }
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 560)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .tint(Theme.text)
    }
}

/// Section header, grouped rows and an optional footnote.
private struct SettingsSection<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: title)
            SettingsGroup { content }
            if let footnote { Text(footnote).font(Theme.caption).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct ModelSettings: View {
    let model: AppModel
    @State private var iterations = Preferences.iterationLimit
    @State private var askForMissingInformation = Preferences.askForMissingInformation
    @State private var managementError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            SettingsSection(title: "On-device model", footnote: "Qwen3 4B, 4-bit quantized · about 2.3 GB download · Apache 2.0. Inference runs on this Mac. The model is stored in Application Support and can be used offline after its first download.") {
                SettingsRow(title: LocalModelManager.modelLabel, detail: model.localModel.state.title) {
                    if case .loading(let progress) = model.localModel.state {
                        HStack(spacing: Theme.Space.sm) {
                            ProgressView(value: progress).frame(width: 120).tint(Theme.text)
                            Text("\(Int(progress * 100))%").font(Theme.caption).foregroundStyle(Theme.textSecondary).monospacedDigit()
                        }
                    } else if model.localModel.state == .generating {
                        StatusIndicator(kind: .busy, label: "Running")
                    } else if model.localModel.state == .ready {
                        StatusIndicator(kind: .ready, label: "Loaded")
                    } else if model.localModel.isInstalled {
                        StatusIndicator(kind: .ready, label: "Downloaded")
                    } else {
                        StatusIndicator(kind: .idle, label: "Not installed")
                    }
                }
                HStack(spacing: Theme.Space.sm) {
                    if case .loading = model.localModel.state {
                        RButton(title: "Cancel download", kind: .secondary) { model.localModel.cancel() }
                    } else if model.localModel.state == .generating {
                        RButton(title: "Cancel generation", kind: .secondary) { model.cancelOptimization() }
                    } else if model.localModel.state == .ready {
                        RButton(title: "Unload from memory", kind: .secondary) { model.localModel.unload() }
                    } else if model.localModel.isInstalled {
                        RButton(title: "Load model", symbol: "arrow.clockwise") { Task { await model.localModel.install() } }
                        RButton(title: "Remove", kind: .ghost) {
                            do { try model.localModel.removeDownloadedModel(); managementError = nil }
                            catch { managementError = error.localizedDescription }
                        }
                    } else {
                        RButton(title: "Download model", symbol: "arrow.down.circle", kind: .primary) { Task { await model.localModel.install() } }
                    }
                    Spacer()
                }
                if case .failed(let message) = model.localModel.state {
                    Text(message).font(Theme.caption).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                }
                if let managementError {
                    Text(managementError).font(Theme.caption).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                }
            }
            SettingsSection(title: "Prompts", footnote: "Refyn asks for missing task details before local optimization. You can skip questions and generate with open questions instead.") {
                SettingsRow(title: "Ask for missing information", detail: "Clarify vague requests before generation.") {
                    RToggle(title: "Ask before optimizing", isOn: $askForMissingInformation)
                }
                SettingsRow(title: "Fix-loop attempts", detail: "How many times an agent may retry before stopping.", divider: false) {
                    Stepper("\(iterations)", value: $iterations, in: 1...10).onChange(of: iterations) { Preferences.iterationLimit = iterations }
                }
            }
        }
        .onChange(of: askForMissingInformation) { Preferences.askForMissingInformation = askForMissingInformation }
    }
}

struct ShortcutSettings: View {
    let onChange: () -> Void
    @State private var toggle = Preferences.toggleShortcut
    @State private var talk = Preferences.pushToTalkShortcut
    @State private var collapse = Preferences.collapseOnFocusLoss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            SettingsSection(title: "Global shortcuts", footnote: "Shortcuts work in every app and need no Accessibility permission.") {
                SettingsRow(title: "Open or collapse Refyn") { ShortcutRecorder(shortcut: $toggle) }
                SettingsRow(title: "Hold to dictate", divider: false) { ShortcutRecorder(shortcut: $talk) }
            }
            SettingsSection(title: "Panel") {
                SettingsRow(title: "Collapse when I switch apps", divider: false) { RToggle(title: "Collapse when I switch apps", isOn: $collapse) }
            }
        }
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
            .buttonStyle(RefynButtonStyle(kind: .secondary))
            .frame(minWidth: 110)
            .help(recording ? "Press Escape to cancel" : "Click to record a new shortcut")
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
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            SettingsSection(title: "Dictation", footnote: "Recording starts only when you press the shortcut or the microphone button. Speech is transcribed on this Mac and never sent to a model automatically.") {
                SettingsRow(title: "After dictation", detail: mode.summary, divider: false) {
                    Segmented(options: VoiceMode.allCases, selection: $mode) { $0.rawValue }
                }
            }
            SettingsSection(title: "Local speech model", footnote: "WhisperKit runs on-device. Larger models are more accurate and slower.") {
                SettingsRow(title: "Model") {
                    Menu {
                        ForEach(SpeechModel.allCases) { m in
                            Button { speechModel = m } label: {
                                if m == speechModel { Label(m.label, systemImage: "checkmark") } else { Text(m.label) }
                            }
                        }
                    } label: { Text(speechModel.label).font(Theme.body) }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                SettingsRow(title: "Status", detail: error, divider: false) {
                    if let p = voice.downloadProgress {
                        HStack(spacing: Theme.Space.sm) {
                            ProgressView(value: p).frame(width: 140).tint(Theme.text)
                            Text("\(Int(p * 100))%").font(Theme.caption).foregroundStyle(Theme.textSecondary).monospacedDigit()
                        }
                    } else if downloaded.contains(speechModel) {
                        StatusIndicator(kind: .ready, label: "Downloaded")
                    } else {
                        RButton(title: "Download", symbol: "arrow.down.circle") {
                            Task {
                                do { try await voice.download(speechModel); downloaded.insert(speechModel); error = nil }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: mode) { Preferences.voiceMode = mode }
        .onChange(of: speechModel) { Preferences.speechModel = speechModel }
    }
}

struct AnalysisSettings: View {
    let model: AppModel
    @State private var nodePath = Preferences.nodePath
    @State private var status = "Checking…"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            SettingsSection(title: "Analysis helper", footnote: "The helper parses code and reads git. It runs only while needed and never executes repository code.") {
                SettingsRow(title: "Node.js path", detail: "Leave blank to auto-detect.") {
                    RTextField(placeholder: "/usr/local/bin/node", text: $nodePath, mono: true).frame(width: 220)
                }
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    RButton(title: "Apply and check") { Task { Preferences.nodePath = nodePath; await model.restartHelper(); await check() } }
                    Text(status).font(Theme.caption).foregroundStyle(Theme.textSecondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(14)
            }
            SettingsSection(title: "Coverage") {
                Text("TypeScript and JavaScript are parsed with the TypeScript compiler. Python, Swift and Prisma use pattern-based extraction. Other languages are counted but not analyzed. Secrets (.env, keys, credentials), dependencies and build output are always excluded.")
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }
        }
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
