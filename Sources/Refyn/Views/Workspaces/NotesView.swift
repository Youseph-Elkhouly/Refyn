import RefineCore
import SwiftUI

struct NotesView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var results: [Note] = []
    @State private var editing: Note?

    var body: some View {
        if model.current == nil {
            EmptyState(symbol: "folder", title: "No workspace", detail: "Notes belong to a workspace.")
        } else {
            HStack(spacing: 0) {
                VStack(spacing: Theme.Space.sm) {
                    HStack(spacing: 6) {
                        SearchField(text: $query, placeholder: "Search notes")
                        IconButton(symbol: "plus", help: "New note (⌘N)") {
                            guard let ws = model.current else { return }
                            let note = Note(workspaceID: ws.id, title: "Untitled")
                            Task { await model.save(note); editing = note }
                        }
                        .keyboardShortcut("n", modifiers: .command)
                    }
                    .padding(.horizontal, 10).padding(.top, 10)
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(results) { note in
                                ListRow(selected: editing?.id == note.id) { editing = note } content: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(note.title.isEmpty ? "Untitled" : note.title).font(Theme.body).lineLimit(1)
                                            if !note.includeInContext {
                                                Image(systemName: "eye.slash").font(.system(size: 9)).foregroundStyle(Theme.textMuted).help("Excluded from AI context")
                                            }
                                        }
                                        Text(note.body.isEmpty ? "Empty" : String(note.body.prefix(80)).replacingOccurrences(of: "\n", with: " "))
                                            .font(Theme.caption).foregroundStyle(Theme.textMuted).lineLimit(1)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    if results.isEmpty { EmptyState(symbol: "note.text", title: query.isEmpty ? "No notes yet" : "No matches") }
                }
                .frame(width: 220)
                Rectangle().fill(Theme.border).frame(width: 1)
                if let note = editing {
                    NoteEditor(note: note, model: model) { editing = nil }.id(note.id)
                } else {
                    EmptyState(symbol: "square.and.pencil", title: "Select a note", detail: "Notes marked for context are included when optimizing.")
                }
            }
            .task(id: query) { results = await model.searchNotes(query) }
            .onChange(of: model.notes) { Task { results = await model.searchNotes(query) } }
        }
    }
}

/// Selectable list row used by Notes and Saved Prompts.
struct ListRow<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .foregroundStyle(Theme.text)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(selected ? Theme.hover : hovering ? Theme.surface : .clear))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(PressDimStyle())
        .onHover { hovering = $0 }
        .motion(Theme.Motion.fast, value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct NoteEditor: View {
    @State var note: Note
    let model: AppModel
    let onDelete: () -> Void
    @State private var saveTask: Task<Void, Never>?
    @State private var saved = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.sm) {
                TextField("Title", text: $note.title, prompt: Text("Title").foregroundStyle(Theme.textMuted)).textFieldStyle(.plain).font(Theme.title)
                Spacer(minLength: 0)
                Text(saved ? "Saved" : "Saving…").font(Theme.caption).foregroundStyle(Theme.textMuted)
                HStack(spacing: 6) {
                    Text("AI context").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    RToggle(title: "Use as AI context", isOn: $note.includeInContext)
                }
                IconButton(symbol: "trash", help: "Delete note") { Task { await model.delete(note); onDelete() } }
            }
            .padding(.horizontal, 16).frame(height: 44)
            Hairline()
            REditor(text: $note.body, placeholder: "Write in Markdown…", font: Theme.body, inset: 12)
                .padding(.horizontal, 6)
                .accessibilityLabel("Note body")
        }
        .onChange(of: note) { _, updated in
            // Debounced autosave.
            saved = false
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await model.save(updated)
                saved = true
            }
        }
    }
}

struct SavedPromptsView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var results: [SavedPrompt] = []
    @State private var selected: SavedPrompt.ID?
    @State private var editing: SavedPrompt?

    var body: some View {
        if model.current == nil {
            EmptyState(symbol: "folder", title: "No workspace", detail: "Saved prompts belong to a workspace.")
        } else {
            VStack(spacing: 0) {
                SearchField(text: $query, placeholder: "Search saved prompts").padding(10)
                if results.isEmpty {
                    EmptyState(symbol: "bookmark", title: query.isEmpty ? "Nothing saved" : "No matches", detail: query.isEmpty ? "Save an optimized prompt to reuse it." : nil)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) { ForEach(results) { row($0) } }.padding(.horizontal, 6).padding(.bottom, 8)
                    }
                }
            }
            .task(id: query) { results = await model.searchSaved(query) }
            .onChange(of: model.savedPrompts) { Task { results = await model.searchSaved(query) } }
            .sheet(item: $editing) { saved in SavedPromptEditor(saved: saved) { updated in Task { await model.update(updated) } } }
        }
    }

    func row(_ saved: SavedPrompt) -> some View {
        let isSelected = selected == saved.id
        return ListRow(selected: isSelected) { selected = isSelected ? nil : saved.id } content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(saved.title).font(Theme.heading).lineLimit(1)
                    Spacer()
                    Text(saved.updatedAt.formatted(.relative(presentation: .named))).font(Theme.caption).foregroundStyle(Theme.textMuted)
                }
                Text(saved.prompt).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(isSelected ? 8 : 2)
                if isSelected {
                    HStack(spacing: 6) {
                        RButton(title: "Copy", symbol: "doc.on.doc", kind: .primary) { model.copy(saved.prompt) }
                        RButton(title: "Open in editor", symbol: "arrow.up.forward") { model.reuse(saved) }
                        RButton(title: "Edit", symbol: "pencil") { editing = saved }
                        Spacer()
                        IconButton(symbol: "trash", help: "Delete") { Task { await model.delete(saved) } }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .motion(Theme.Motion.base, value: isSelected)
    }
}

struct SavedPromptEditor: View {
    @State var saved: SavedPrompt
    let onSave: (SavedPrompt) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Edit saved prompt")
            RTextField(placeholder: "Title", text: $saved.title)
            REditor(text: $saved.prompt, placeholder: "Prompt", font: Theme.prompt, inset: 8)
                .frame(minHeight: 260)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.input))
                .hairlineBorder(Theme.Radius.md)
            HStack {
                Spacer()
                RButton(title: "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                RButton(title: "Save", kind: .primary) { onSave(saved); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.lg).frame(width: 560)
        .background(Theme.background)
        .preferredColorScheme(.light)
    }
}
