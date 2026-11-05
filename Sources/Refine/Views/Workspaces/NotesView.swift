import RefineCore
import SwiftUI

struct NotesView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var results: [Note] = []
    @State private var editing: Note?

    var body: some View {
        if model.current == nil {
            ContentUnavailableView("No workspace", systemImage: "folder", description: Text("Notes belong to a workspace."))
        } else {
            HStack(spacing: 0) {
                VStack(spacing: 8) {
                    HStack {
                        SearchField(text: $query, placeholder: "Search notes")
                        IconButton(symbol: "plus", help: "New note") {
                            guard let ws = model.current else { return }
                            let note = Note(workspaceID: ws.id, title: "Untitled")
                            Task { await model.save(note); editing = note }
                        }
                    }
                    List(selection: Binding(get: { editing?.id }, set: { id in editing = results.first { $0.id == id } })) {
                        ForEach(results) { note in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(note.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                    if !note.includeInContext { Image(systemName: "eye.slash").font(.system(size: 9)).foregroundStyle(Theme.tertiary).help("Excluded from AI context") }
                                }
                                Text(note.body.prefix(80)).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                            }
                            .tag(note.id)
                        }
                    }
                    .listStyle(.sidebar).scrollContentBackground(.hidden)
                }
                .frame(width: 210)
                .padding(10)
                Divider().overlay(Theme.stroke)
                if let note = editing {
                    NoteEditor(note: note, model: model) { editing = nil }.id(note.id)
                } else {
                    ContentUnavailableView("Select a note", systemImage: "note.text", description: Text("Notes marked for context are included when optimizing."))
                }
            }
            .task(id: query) { results = await model.searchNotes(query) }
            .onChange(of: model.notes) { Task { results = await model.searchNotes(query) } }
        }
    }
}

struct NoteEditor: View {
    @State var note: Note
    let model: AppModel
    let onDelete: () -> Void
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Title", text: $note.title).textFieldStyle(.plain).font(.system(size: 15, weight: .semibold))
                Toggle("Use as AI context", isOn: $note.includeInContext).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                IconButton(symbol: "trash", help: "Delete note") { Task { await model.delete(note); onDelete() } }
            }
            TextEditor(text: $note.body).font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden)
                .padding(6).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
            Text("Markdown. Saved automatically.").font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
        }
        .padding(12)
        .onChange(of: note) { _, updated in
            // Debounced autosave.
            saveTask?.cancel()
            saveTask = Task { try? await Task.sleep(for: .milliseconds(500)); if !Task.isCancelled { await model.save(updated) } }
        }
    }
}

struct SavedPromptsView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var results: [SavedPrompt] = []
    @State private var editing: SavedPrompt?

    var body: some View {
        if model.current == nil {
            ContentUnavailableView("No workspace", systemImage: "folder", description: Text("Saved prompts belong to a workspace."))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SearchField(text: $query, placeholder: "Search saved prompts")
                if results.isEmpty {
                    ContentUnavailableView("Nothing saved", systemImage: "bookmark", description: Text("Save an optimized prompt to reuse it."))
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { saved in row(saved) }
                    }
                }
            }
            .padding(14)
            .task(id: query) { results = await model.searchSaved(query) }
            .onChange(of: model.savedPrompts) { Task { results = await model.searchSaved(query) } }
            .sheet(item: $editing) { saved in SavedPromptEditor(saved: saved) { updated in Task { await model.update(updated) } } }
        }
    }

    func row(_ saved: SavedPrompt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(saved.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(saved.updatedAt.formatted(.relative(presentation: .named))).font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
            }
            Text(saved.prompt).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.secondary).lineLimit(3)
            HStack(spacing: 6) {
                Button("Copy") { model.copy(saved.prompt) }.buttonStyle(PillButtonStyle(prominent: true))
                Button("Reuse") { model.reuse(saved) }.buttonStyle(PillButtonStyle()).help("Open in the editor")
                Button("Edit") { editing = saved }.buttonStyle(PillButtonStyle())
                Spacer()
                IconButton(symbol: "trash", help: "Delete") { Task { await model.delete(saved) } }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    }
}

struct SavedPromptEditor: View {
    @State var saved: SavedPrompt
    let onSave: (SavedPrompt) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $saved.title).textFieldStyle(.roundedBorder)
            TextEditor(text: $saved.prompt).font(.system(size: 12.5, design: .monospaced)).frame(minHeight: 260)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { onSave(saved); dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(16).frame(width: 560)
    }
}
