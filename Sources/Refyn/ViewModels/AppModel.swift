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
    struct ClarificationState {
        var requestText: String
        var gaps: [RequirementGap]
        var answers: [String: String]
    }
    private struct ClarificationResolution {
        var answers: [PromptAnswer]
        var unanswered: [String]
    }

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
    var clarification: ClarificationState?
    private var clarificationResolutions: [String: ClarificationResolution] = [:]
    var agentID = Preferences.agentID { didSet { Preferences.agentID = agentID } }

    var banner: Banner?
    let voice = VoiceController()
    let localModel = LocalModelManager()

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
            show("Removed \(workspace.name) from Refyn. The folder itself was not touched.")
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

    func optimize(regenerate: Bool = false) async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { show(PromptError.emptyInput.localizedDescription, .warning); return }
        let key = Self.clarificationKey(text)
        let resolution = clarificationResolutions[key]
        if !regenerate, resolution == nil, Preferences.askForMissingInformation {
            let analysis = RequestAnalysis(text)
            let context = ContextRetriever.retrieve(for: analysis, workspaceName: current?.name ?? "", graph: workspaceGraph, notes: notes)
            let gaps = analysis.gaps(context: context)
            if !gaps.isEmpty {
                clarification = ClarificationState(requestText: text, gaps: gaps, answers: [:])
                return
            }
        }
        await performOptimization(text: text, answers: resolution?.answers ?? [], unanswered: resolution?.unanswered ?? [], regenerate: regenerate)
    }

    func setClarificationAnswer(_ answer: String, for gapID: String) {
        clarification?.answers[gapID] = answer
    }

    func continueClarification() async {
        guard let state = clarification else { return }
        let answers = state.gaps.compactMap { gap -> PromptAnswer? in
            guard let value = state.answers[gap.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return PromptAnswer(id: gap.id, question: gap.question, answer: value)
        }
        let answeredIDs = Set(answers.map(\.id))
        let unanswered = state.gaps.filter { !answeredIDs.contains($0.id) }.map(\.question)
        clarificationResolutions[Self.clarificationKey(state.requestText)] = ClarificationResolution(answers: answers, unanswered: unanswered)
        clarification = nil
        await persistClarificationAnswers(answers, for: state.gaps.first?.taskType)
        await performOptimization(text: state.requestText, answers: answers, unanswered: unanswered, regenerate: false)
    }

    func skipClarification() async {
        guard let state = clarification else { return }
        let unanswered = state.gaps.map(\.question)
        clarificationResolutions[Self.clarificationKey(state.requestText)] = ClarificationResolution(answers: [], unanswered: unanswered)
        clarification = nil
        await performOptimization(text: state.requestText, answers: [], unanswered: unanswered, regenerate: false)
    }

    /// Escape returns to the draft. The same request won't ask again; its gaps remain available to generation.
    func cancelClarification() {
        guard let state = clarification else { return }
        clarificationResolutions[Self.clarificationKey(state.requestText)] = ClarificationResolution(answers: [], unanswered: state.gaps.map(\.question))
        clarification = nil
    }

    private func persistClarificationAnswers(_ answers: [PromptAnswer], for taskType: TaskType?) async {
        guard let workspace = current, !answers.isEmpty else { return }
        let body = answers.map { "### \($0.question)\n\n\($0.answer)" }.joined(separator: "\n\n")
        let note = Note(workspaceID: workspace.id, title: "Prompt clarifications · \(taskType?.rawValue ?? "task")", body: body, includeInContext: true)
        do {
            try await store.save(note)
            notes = try await store.notes(workspaceID: workspace.id)
            show("Clarification answers saved as a workspace note.")
        } catch { show("Could not save clarification answers: \(error.localizedDescription)", .error) }
    }

    private static func clarificationKey(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func performOptimization(text: String, answers: [PromptAnswer], unanswered: [String], regenerate: Bool) async {
        guard !isOptimizing else { return }
        isOptimizing = true
        defer { isOptimizing = false }
        banner = nil
        let provider: (any LLMProvider)? = LocalLLMProvider(manager: localModel)
        let optimizer = PromptOptimizer(provider: provider)
        let input = PromptOptimizer.Input(text: text, mode: mode, customTechniques: customTechniques, workspace: current, graph: workspaceGraph,
                                          notes: notes, iterationLimit: Preferences.iterationLimit, userAnswers: answers, unansweredQuestions: unanswered)
        do {
            // Identical inputs reuse the stored plan instead of calling the model again.
            if !regenerate, let cached = try await store.cachedPlan(cacheKey: optimizer.cacheKey(for: input)), cached.provider == LocalModelManager.modelID {
                plan = cached
                show("Reused the plan from an identical earlier request.")
            } else {
                let result = try await optimizer.optimize(input)
                try await store.save(result)
                plan = result
                if let notice = result.notices.first { show(notice, .warning) }
            }
            route = .result
        } catch {
            if (error as? LLMError) != .cancelled { show(error.localizedDescription, .error) }
        }
    }

    func cancelOptimization() {
        localModel.cancel()
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
        if mode == .optimize { Task { await optimize() } }
    }
}
