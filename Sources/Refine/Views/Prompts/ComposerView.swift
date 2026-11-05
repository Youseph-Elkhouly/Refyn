import RefineCore
import SwiftUI

struct ComposerView: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool
    @State private var showTechniques = false

    private var canOptimize: Bool { !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            editor
            Hairline()
            controls
            footer
        }
        .task { await focusEditor() }
    }

    /// The panel becomes key a moment after the view appears, so retry once.
    func focusEditor() async {
        focused = true
        try? await Task.sleep(for: .milliseconds(120))
        focused = true
    }

    var editor: some View {
        ZStack(alignment: .bottomTrailing) {
            REditor(text: $model.input, placeholder: "What are you working on?", inset: 14, focus: $focused)
                .padding(.horizontal, 6)
                .accessibilityLabel("Prompt")
            if model.voice.state == .recording || model.voice.state == .transcribing {
                HStack(spacing: Theme.Space.sm) {
                    if model.voice.state == .recording { Waveform(levels: model.voice.levels); Text("Listening…") }
                    else { StatusIndicator(kind: .busy); Text("Transcribing on this Mac…") }
                }
                .font(Theme.caption).foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Theme.surface)).overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                .padding(Theme.Space.md)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .motion(Theme.Motion.base, value: model.voice.state)
    }

    var controls: some View {
        HStack(spacing: Theme.Space.sm) {
            IconButton(symbol: model.voice.isRecording ? "stop.fill" : "mic", help: model.voice.isRecording ? "Stop dictation" : "Dictate (or hold \(Preferences.pushToTalkShortcut.display))", active: model.voice.isRecording) {
                model.voice.toggle()
            }
            .disabled(model.voice.state == .transcribing)

            Segmented(options: PromptMode.allCases, selection: $model.mode) { $0.rawValue }
                .help(modeHelp)

            if model.mode == .custom {
                IconButton(symbol: "slider.horizontal.3", help: "Choose techniques", active: showTechniques) { showTechniques.toggle() }
                    .popover(isPresented: $showTechniques, arrowEdge: .bottom) { techniquePicker }
            }

            Spacer(minLength: Theme.Space.sm)
            KeyHint(text: "⌘↩")
            RButton(title: model.isOptimizing ? "Optimizing" : "Optimize", kind: .primary, loading: model.isOptimizing) { Task { await model.optimize() } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canOptimize)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    var modeHelp: String {
        switch model.mode {
        case .auto: "Chooses techniques from the request's complexity."
        case .basic: "Clarifies without expanding."
        case .advanced: "Planning, constraints, dependencies and verification."
        case .custom: "Pick techniques yourself."
        }
    }

    var techniquePicker: some View {
        let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.sm) {
                ForEach(PromptTechnique.allCases) { t in
                    Toggle(isOn: Binding(get: { model.customTechniques.contains(t) },
                                         set: { on in if on { model.customTechniques.insert(t) } else { model.customTechniques.remove(t) } })) {
                        Text(t.rawValue).font(Theme.caption)
                    }
                    .toggleStyle(.checkbox)
                    .help(t.summary)
                }
            }
            .padding(Theme.Space.lg)
        }
        .frame(width: 360, height: 280)
    }

    var footer: some View {
        HStack(spacing: Theme.Space.md) {
            if case .failed(let message) = model.voice.state {
                Label(message, systemImage: "mic.slash").foregroundStyle(Theme.textSecondary).lineLimit(2)
                Button("Dismiss") { model.voice.clearError() }.buttonStyle(.plain).foregroundStyle(Theme.text)
            } else if model.current == nil {
                Button("Choose a workspace for context") { if let url = AppActions.chooseFolder() { Task { await model.addWorkspace(url) } } }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            } else if let snap = model.verifiedSnapshot {
                Text("\(snap.graph.nodes.count) components in context").help("Context comes from the last verified analysis (v\(snap.version)).")
            }
            if model.execution != nil {
                Button { Task { await model.startReview() } } label: { Label("Review changes", systemImage: "checklist") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("\(Preferences.toggleShortcut.display) toggle · hold \(Preferences.pushToTalkShortcut.display) to dictate")
        }
        .font(Theme.caption).foregroundStyle(Theme.textMuted)
        .padding(.horizontal, 16).padding(.bottom, 10)
    }
}
