import RefineCore
import SwiftUI

struct ComposerView: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool
    @FocusState private var focusedAnswer: String?
    @State private var showTechniques = false

    private var canOptimize: Bool { !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if let clarification = model.clarification {
                clarificationView(clarification)
            } else {
                editor
                Hairline()
                controls
                footer
            }
        }
        .task { await focusEditor() }
        .onChange(of: model.isExpanded) { if model.isExpanded { Task { await focusEditor() } } }
        .onExitCommand { model.cancelClarification() }
    }

    /// The panel becomes key a moment after the view appears, so retry once.
    func focusEditor() async {
        guard model.isExpanded, model.clarification == nil else { return }
        focused = true
        try? await Task.sleep(for: .milliseconds(120))
        if model.clarification == nil { focused = true }
    }

    var editor: some View {
        ZStack(alignment: .bottomTrailing) {
            REditor(text: $model.input, placeholder: "What are you working on?", inset: 14, focus: $focused)
                .padding(.horizontal, 6)
                .accessibilityLabel("Prompt")
                .help("Type your request here. Use ⌘C to copy and ⌘V to paste selected text.")
            if model.isExpanded, model.voice.state == .recording || model.voice.state == .transcribing {
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

    func clarificationView(_ state: AppModel.ClarificationState) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Needs your input")
                Spacer()
                Text("\(state.gaps.count) questions").font(Theme.caption).foregroundStyle(Theme.textMuted)
            }
            Text(state.requestText).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)

            ForEach(state.gaps) { gap in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    FieldLabel(gap.question)
                    RTextField(placeholder: "Your answer (optional)",
                               text: Binding(get: { model.clarification?.answers[gap.id] ?? "" },
                                             set: { model.setClarificationAnswer($0, for: gap.id) }),
                               focus: $focusedAnswer, focusID: gap.id)
                }
            }

            HStack(spacing: Theme.Space.sm) {
                RButton(title: "Back", kind: .ghost) { model.cancelClarification() }
                    .keyboardShortcut(.escape, modifiers: [])
                RButton(title: "Skip and generate", kind: .secondary) { Task { await model.skipClarification() } }
                Spacer()
                RButton(title: "Continue", symbol: "arrow.right", kind: .primary) { Task { await model.continueClarification() } }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            Text("Answers are saved as a deletable workspace note when a workspace is selected.")
                .font(Theme.caption).foregroundStyle(Theme.textMuted)
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { focusedAnswer = state.gaps.first?.id }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clarification questions")
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
                IconButton(symbol: "slider.horizontal.3", help: "Customize how Refyn improves your prompt", active: showTechniques) { showTechniques.toggle() }
                    .popover(isPresented: $showTechniques, arrowEdge: .bottom) { techniquePicker }
            }

            Spacer(minLength: Theme.Space.sm)
            if model.isOptimizing {
                HStack(spacing: Theme.Space.xs) {
                    ProgressView().controlSize(.small).tint(Theme.text)
                    Text("Running locally").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            KeyHint(text: "⌘↩")
            RButton(title: model.isOptimizing ? "Cancel" : "Optimize", symbol: model.isOptimizing ? "xmark" : nil, kind: .primary) {
                if model.isOptimizing { model.cancelOptimization() }
                else { Task { await model.optimize() } }
            }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canOptimize && !model.isOptimizing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    var modeHelp: String {
        switch model.mode {
        case .auto: "Refyn chooses how much detail your request needs."
        case .basic: "Make your request clearer and keep it concise."
        case .advanced: "Add steps, requirements, and checks for larger tasks."
        case .custom: "Choose what Refyn adds to your prompt."
        }
    }

    var techniquePicker: some View {
        let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
        return VStack(alignment: .leading, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionHeader(title: "Choose what Refyn adds")
                Text("Pick any options that help. Leave them off to keep your prompt simple.")
                    .font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.sm) {
                    ForEach(PromptTechnique.allCases) { t in
                        Toggle(isOn: Binding(get: { model.customTechniques.contains(t) },
                                             set: { on in if on { model.customTechniques.insert(t) } else { model.customTechniques.remove(t) } })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.displayTitle).font(Theme.body).foregroundStyle(Theme.text)
                                Text(t.userDescription).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(.checkbox)
                        .help(t.userDescription)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 560, height: 440)
    }

    var footer: some View {
        HStack(spacing: Theme.Space.md) {
            if case .failed(let message) = model.voice.state {
                Label(message, systemImage: "mic.slash").foregroundStyle(Theme.textSecondary).lineLimit(2)
                Button("Dismiss") { model.voice.clearError() }.buttonStyle(.plain).foregroundStyle(Theme.text)
            } else if model.current == nil {
                Button("Choose a workspace for context") { if let url = AppActions.chooseFolder() { Task { await model.addWorkspace(url) } } }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            } else if let graph = model.workspaceGraph {
                Text("\(graph.nodes.count) components in context").help("Context comes from local workspace analysis.")
            }
            Spacer()
            Text("\(Preferences.toggleShortcut.display) toggle · hold \(Preferences.pushToTalkShortcut.display) to dictate")
        }
        .font(Theme.caption).foregroundStyle(Theme.textMuted)
        .padding(.horizontal, 16).padding(.bottom, 10)
    }
}
