import RefineCore
import SwiftUI

struct ComposerView: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool
    @State private var showTechniques = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "What should your agent do?")
                Spacer()
                if model.current == nil {
                    Button("Choose a workspace for context") { if let url = AppActions.chooseFolder() { Task { await model.addWorkspace(url) } } }
                        .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                } else if let snap = model.verifiedSnapshot {
                    Text("\(snap.graph.nodes.count) components · v\(snap.version)").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        .help("Context comes from the last verified architecture snapshot.")
                }
            }
            editor
            controls
            if model.mode == .custom { techniquePicker }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .onAppear { focused = true }
    }

    var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.input)
                .font(.system(size: 14.5))
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(8)
            if model.input.isEmpty {
                Text("Describe the change, rough edges and all. Refine shapes it into a prompt your agent can execute.")
                    .font(.system(size: 14)).foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            if model.voice.state == .recording || model.voice.state == .transcribing {
                HStack(spacing: 8) {
                    if model.voice.state == .recording { Waveform(levels: model.voice.levels, color: Theme.danger); Text("Listening…") }
                    else { ProgressView().controlSize(.small); Text("Transcribing locally…") }
                }
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                .padding(8).background(Capsule().fill(Theme.raised))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(8)
            }
        }
        .frame(minHeight: 170, maxHeight: 260)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(focused ? Theme.accent.opacity(0.45) : Theme.stroke))
    }

    var controls: some View {
        HStack(spacing: 10) {
            Button { model.voice.toggle() } label: {
                Image(systemName: model.voice.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 13)).frame(width: 30, height: 28)
                    .foregroundStyle(model.voice.isRecording ? Theme.danger : Theme.text)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("Dictate (or hold \(Preferences.pushToTalkShortcut.display))")
            .disabled(model.voice.state == .transcribing)

            Picker("Mode", selection: $model.mode) {
                ForEach(PromptMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 270)
            .help(modeHelp)

            Spacer()
            if model.isOptimizing { ProgressView().controlSize(.small) }
            Button { Task { await model.optimize() } } label: { Label("Optimize", systemImage: "sparkles") }
                .buttonStyle(PillButtonStyle(prominent: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.isOptimizing || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
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
        let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(PromptTechnique.allCases) { t in
                Toggle(isOn: Binding(get: { model.customTechniques.contains(t) },
                                     set: { on in if on { model.customTechniques.insert(t) } else { model.customTechniques.remove(t) } })) {
                    Text(t.rawValue).font(.system(size: 11.5))
                }
                .toggleStyle(.checkbox)
                .help(t.summary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
    }

    var footer: some View {
        HStack(spacing: 12) {
            if case .failed(let message) = model.voice.state {
                Label(message, systemImage: "mic.slash").foregroundStyle(Theme.warning).lineLimit(2)
                Button("Dismiss") { model.voice.clearError() }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            } else if model.execution != nil {
                Button { Task { await model.startReview() } } label: { Label("Review changes from the last hand-off", systemImage: "checklist") }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            Spacer()
            Text("⌘↩ optimize · \(Preferences.toggleShortcut.display) toggle · hold \(Preferences.pushToTalkShortcut.display) to dictate")
                .foregroundStyle(Theme.tertiary)
        }
        .font(.system(size: 11))
    }
}
