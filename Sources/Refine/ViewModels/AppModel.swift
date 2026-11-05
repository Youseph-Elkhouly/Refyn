import AppKit
import Observation
import RefineCore

/// App-wide state for the notch panel. Views read it; services do the work.
@Observable
@MainActor
final class AppModel {
    enum Route: Equatable { case compose, result, notes, saved }
    enum AnalysisState: Equatable { case idle, running, failed(String) }
    struct Banner: Equatable { enum Kind { case info, warning, error }; var text: String; var kind: Kind }

    // Panel
    var isExpanded = false
    var route: Route = .compose

    // Workspaces
    private(set) var workspaces: [Workspace] = []
    private(set) var current: Workspace?
    private(set) var notes: [Note] = []
    private(set) var savedPrompts: [SavedPrompt] = []
    private(set) var workspaceGraph: CodebaseGraph?
    private(set) var analysis: AnalysisState = .idle

    // Prompting
    var input = ""
    var mode: PromptMode = Preferences.mode { didSet { Preferences.mode = mode } }
    var customTechniques: Set<PromptTechnique> = Preferences.customTechniques { didSet { Preferences.customTechniques = customTechniques } }
    var plan: PromptPlan?
    private(set) var isOptimizing = false
    var agentID = Preferences.agentID { didSet { Preferences.agentID = agentID } }

    var banner: Banner?
    let voice = VoiceController()

    let store: WorkspaceStore
    private(set) var helper: HelperClient
    private(set) var analyzer: WorkspaceAnalyzer
    var onExpand: () -> Void = {}
    var onCollapse: () -> Void = {}


    init(store: WorkspaceStore) {
        self.store = store
        let helper = HelperClient(nodePath: Preferences.nodePath)
        self.helper = helper
        analyzer = WorkspaceAnalyzer(helper: helper)
        voice.onTranscript = { [weak self] text in self?.receiveTranscript(text) }
    }

    func load() async {
        await reloadWorkspaces()
        let preferred = workspaces.first { $0.id == Preferences.lastWorkspaceID } ?? workspaces.first
        if let preferred { await select(preferred, scanIfNeeded: true) }
    }

    /// Recreates the helper after Node settings change.
    func restartHelper() async {
        await helper.stop()
        helper = HelperClient(nodePath: Preferences.nodePath)
        analyzer = WorkspaceAnalyzer(helper: helper)
    }

    func shutdown() async { await helper.stop() }

    func show(_ text: String, _ kind: Banner.Kind = .info) {
        let shown = Banner(text: text, kind: kind)
        banner = shown
        guard kind == .info else { return }
        Task { try? await Task.sleep(for: .seconds(4)); if banner == shown { banner = nil } }
    }

    // MARK: Workspaces

    func reloadWorkspaces() async {
        do { workspaces = try await store.workspaces() } catch { show(error.localizedDescription, .error) }
    }

    func addWorkspace(_ url: URL) async {
        do {
            let ws = try await store.addDirectory(url)
            await reloadWorkspaces()
            await select(ws, scanIfNeeded: true)
        } catch { show(error.localizedDescription, .error) }
    }

    func select(_ workspace: Workspace, scanIfNeeded: Bool = true) async {
        current = workspace
        Preferences.lastWorkspaceID = workspace.id
        plan = nil
        route = .compose
        try? await store.touch(workspace.id)
        await reloadWorkspaceData()
        // Scans run only for a newly chosen workspace or on request, never continuously in the background.
        if scanIfNeeded && workspaceGraph == nil { await analyze() }
    }

    func rename(_ workspace: Workspace, to name: String) async {
        do { try await store.rename(workspace.id, to: name) } catch { show(error.localizedDescription, .error) }
        await reloadWorkspaces()
        if current?.id == workspace.id { current = workspaces.first { $0.id == workspace.id } }
    }

    func remove(_ workspace: Workspace) async {
        do {
            try await store.remove(workspace.id)
            show("Removed \(workspace.name) from Refine. The folder itself was not touched.")
        } catch { show(error.localizedDescription, .error) }
        await reloadWorkspaces()
        if current?.id == workspace.id {
            current = nil
            if let next = workspaces.first { await select(next, scanIfNeeded: false) } else { notes = []; savedPrompts = []; workspaceGraph = nil }
        }
    }

    func reloadWorkspaceData() async {
        guard let ws = current else { return }
        do {
            notes = try await store.notes(workspaceID: ws.id)
            savedPrompts = try await store.savedPrompts(workspaceID: ws.id)
            workspaceGraph = nil
        } catch { show(error.localizedDescription, .error) }
    }

    func analyze() async {
        guard let ws = current, analysis != .running else { return }
        analysis = .running
        do {
            workspaceGraph = try await analyzer.analyze(ws).graph
            analysis = .idle
        } catch {
            analysis = .failed(error.localizedDescription)
        }
    }

    // MARK: Notes and saved prompts

    func save(_ note: Note) async {
        var n = note
        n.updatedAt = .now
        do { try await store.save(n) } catch { show(error.localizedDescription, .error) }
        await reloadWorkspaceData()
    }

    func delete(_ note: Note) async {
        do { try await store.deleteNote(note.id) } catch { show(error.localizedDescription, .error) }
        await reloadWorkspaceData()
    }

    func searchNotes(_ query: String) async -> [Note] {
        guard let ws = current else { return [] }
        return (try? await store.notes(workspaceID: ws.id, matching: query)) ?? []
    }

    func savePrompt(title: String? = nil) async {
        guard let ws = current, let plan else { show("Choose a workspace to save prompts.", .warning); return }
        let saved = SavedPrompt(workspaceID: ws.id, title: title ?? String(plan.intent.prefix(60)), prompt: plan.optimizedPrompt, planID: plan.id)
        do { try await store.save(saved); show("Saved.") } catch { show(error.localizedDescription, .error) }
        await reloadWorkspaceData()
    }

    func update(_ saved: SavedPrompt) async {
        var s = saved
        s.updatedAt = .now
        do { try await store.save(s) } catch { show(error.localizedDescription, .error) }
        await reloadWorkspaceData()
    }

    func delete(_ saved: SavedPrompt) async {
        do { try await store.deleteSavedPrompt(saved.id) } catch { show(error.localizedDescription, .error) }
        await reloadWorkspaceData()
    }

    func searchSaved(_ query: String) async -> [SavedPrompt] {
        guard let ws = current else { return [] }
        return (try? await store.savedPrompts(workspaceID: ws.id, matching: query)) ?? []
    }

    func reuse(_ saved: SavedPrompt) {
        input = saved.prompt
        plan = nil
        route = .compose
    }

    // MARK: Optimizing

    func optimize(useModel: Bool = true, regenerate: Bool = false) async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { show(PromptError.emptyInput.localizedDescription, .warning); return }
        guard !isOptimizing else { return }
        isOptimizing = true
        defer { isOptimizing = false }
        banner = nil
        let key = useModel ? Preferences.keychain.read(Preferences.geminiAccount) : nil
        let provider: (any LLMProvider)? = key.map { GeminiProvider(apiKey: $0, model: Preferences.geminiModel) }
        let optimizer = PromptOptimizer(provider: provider)
        let input = PromptOptimizer.Input(text: text, mode: mode, customTechniques: customTechniques, workspace: current, graph: workspaceGraph,
                                          notes: notes, iterationLimit: Preferences.iterationLimit)
        do {
            // Identical inputs reuse the stored plan instead of calling the model again.
            if provider != nil, !regenerate, let cached = try await store.cachedPlan(cacheKey: optimizer.cacheKey(for: input)), cached.provider != "local" {
                plan = cached
                show("Reused the plan from an identical earlier request.")
            } else {
                let result = try await optimizer.optimize(input)
                try await store.save(result)
                plan = result
                if key == nil && useModel { show("Add a Gemini API key in Settings for model-assisted prompts. This one was built locally.", .warning) }
                else if let notice = result.notices.first(where: { !$0.hasPrefix("Built locally (no model") }) { show(notice, .warning) }
            }
            route = .result
        } catch {
            show(error.localizedDescription, .error)
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show("Copied.")
    }

    // MARK: Voice

    private func receiveTranscript(_ text: String) {
        let mode = Preferences.voiceMode
        let processed = mode == .transcribe ? text : TranscriptCleaner.clean(text)
        input = input.isEmpty ? processed : input + (input.hasSuffix(" ") || input.hasSuffix("\n") ? "" : " ") + processed
        route = .compose
        onExpand()
        if mode == .optimize { Task { await optimize(useModel: false) } }
    }
}
