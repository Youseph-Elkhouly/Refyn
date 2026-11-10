import RefineCore
import SwiftUI

struct ResultView: View {
    @Bindable var model: AppModel
    enum Tab: String, CaseIterable { case prompt = "Prompt", plan = "Plan" }
    @State private var tab: Tab = .prompt
    @State private var stage = -1
    @State private var isEditing = false
    @State private var editedText = ""
    @State private var isAddingContext = false
    @State private var additionalContext = ""
    @FocusState private var contextFocused: Bool

    var body: some View {
        if let plan = model.plan {
            VStack(alignment: .leading, spacing: 0) {
                original(plan)
                if isAddingContext { addContextEditor(plan) }
                Hairline()
                toolbar(plan)
                ZStack {
                    ScrollView {
                        Group {
                            switch tab {
                            case .prompt:
                                if isEditing {
                                    TextEditor(text: $editedText)
                                        .font(Theme.prompt)
                                        .scrollContentBackground(.hidden)
                                        .foregroundStyle(Theme.text)
                                        .accessibilityLabel("Edit optimized prompt")
                                } else {
                                    Text(currentText(plan)).font(Theme.prompt).lineSpacing(Theme.lineSpacing)
                                }
                            case .plan: PlanDetails(plan: plan)
                            }
                        }
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 18).padding(.bottom, Theme.Space.md)
                    }
                    .opacity(model.isOptimizing ? 0.35 : 1)
                    if model.isOptimizing { LoadingState(label: "Regenerating…") }
                }
                .motion(Theme.Motion.base, value: model.isOptimizing)
                Hairline()
                actions(plan)
            }
            .onChange(of: plan.id) {
                stage = -1
                tab = .prompt
                isEditing = false
                editedText = ""
                additionalContext = ""
                isAddingContext = false
                contextFocused = false
            }
        } else {
            EmptyState(symbol: "text.append", title: "No prompt yet", detail: "Write a request and choose Optimize.", actionTitle: "Open editor") { model.route = .compose }
        }
    }

    func original(_ plan: PromptPlan) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                FieldLabel("Your request")
                Text(plan.originalPrompt).font(Theme.body).foregroundStyle(Theme.textSecondary).lineLimit(2).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            RButton(title: isAddingContext ? "Cancel" : "Add context", symbol: isAddingContext ? "xmark" : "plus", kind: .ghost) {
                isAddingContext.toggle()
                if isAddingContext {
                    tab = .prompt
                    stage = -1
                    isEditing = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { contextFocused = true }
                } else {
                    additionalContext = ""
                    contextFocused = false
                }
            }
            .disabled(model.isOptimizing)
            .help("Add a detail and update this optimized prompt")
            RButton(title: "Edit", symbol: "pencil", kind: .ghost) { model.route = .compose }.help("Back to the editor with your text")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    func toolbar(_ plan: PromptPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                Segmented(options: Tab.allCases, selection: $tab) { $0.rawValue }
                if tab == .prompt && !plan.chainedPrompts.isEmpty {
                    Segmented(options: [-1] + Array(plan.chainedPrompts.indices), selection: $stage) { $0 < 0 ? "Full" : "Step \($0 + 1)" }
                }
                Spacer()
                Chip(text: plan.provider == "local" ? "Local rules" : plan.provider == LocalModelManager.modelID ? "Qwen3 · on-device" : plan.provider)
                if plan.revisionOf != nil { Chip(text: "Updated") }
                Chip(text: plan.taskType.rawValue)
                if !plan.validation.passed {
                    Chip(text: plan.validation.repaired ? "Original quoted" : "Check intent")
                        .help(plan.validation.missingTerms.isEmpty ? "The model reported it may have changed your intent." :
                                "These terms from your request were missing, so the original request is quoted: \(plan.validation.missingTerms.joined(separator: ", "))")
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    @ViewBuilder
    func addContextEditor(_ plan: PromptPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            FieldLabel("What did you remember?")
            REditor(text: $additionalContext, placeholder: "Add a detail to include in this prompt…", font: Theme.body, inset: 8, focus: $contextFocused)
                .frame(height: 62)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.input))
                .hairlineBorder(Theme.Radius.md)
                .disabled(model.isOptimizing)
                .accessibilityLabel("Additional prompt context")

            HStack(spacing: Theme.Space.sm) {
                Text("The earlier result stays in prompt history.")
                    .font(Theme.caption).foregroundStyle(Theme.textMuted)
                Spacer()
                RButton(title: model.isOptimizing ? "Cancel" : "Re-optimize", symbol: model.isOptimizing ? "xmark" : "arrow.clockwise", kind: .primary) {
                    if model.isOptimizing {
                        model.cancelOptimization()
                    } else {
                        let priorID = plan.id
                        Task {
                            await model.reoptimizeAddingContext(additionalContext)
                            if model.plan?.id != priorID {
                                additionalContext = ""
                                isAddingContext = false
                                contextFocused = false
                            }
                        }
                    }
                }
                .disabled(!model.isOptimizing && additionalContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .motion(Theme.Motion.base, value: isAddingContext)
    }

    func actions(_ plan: PromptPlan) -> some View {
        HStack(spacing: Theme.Space.sm) {
            RButton(title: "Copy", symbol: "doc.on.doc", kind: .primary) { model.copy(currentText(plan)) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy the prompt (⇧⌘C)")
            RButton(title: "Save", symbol: "bookmark") { Task { await model.savePrompt() } }
            RButton(title: isEditing ? "Done" : "Edit output", symbol: isEditing ? "checkmark" : "pencil") {
                if isEditing { saveEditedText() }
                else { editedText = currentText(plan); isEditing = true }
            }
                .disabled(model.isOptimizing || tab != .prompt)
            RButton(title: model.isOptimizing ? "Cancel" : "Regenerate", symbol: model.isOptimizing ? "xmark" : "arrow.clockwise") {
                if model.isOptimizing { model.cancelOptimization() }
                else { Task { await model.optimize(regenerate: true) } }
            }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("Build the prompt again (⇧⌘R)")
            Spacer()
            Menu {
                ForEach(AgentRegistry.all, id: \.id) { agent in
                    Button { model.agentID = agent.id } label: {
                        if agent.id == model.agentID { Label(agent.displayName, systemImage: "checkmark") } else { Text(agent.displayName) }
                    }
                }
            } label: {
                Text("For \(AgentRegistry.adapter(model.agentID).displayName)").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Where you'll paste the prompt")
            IconButton(symbol: "plus", help: "New prompt") { model.input = ""; model.plan = nil; model.route = .compose }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    func currentText(_ plan: PromptPlan) -> String {
        if tab == .prompt, plan.chainedPrompts.indices.contains(stage) { return plan.chainedPrompts[stage] }
        return plan.optimizedPrompt
    }

    func saveEditedText() {
        guard var updated = model.plan else { return }
        if updated.chainedPrompts.indices.contains(stage) { updated.chainedPrompts[stage] = editedText }
        else { updated.optimizedPrompt = editedText }
        model.plan = updated
        isEditing = false
    }
}

struct PlanDetails: View {
    let plan: PromptPlan
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            row("Intent", [plan.intent])
            row("Confirmed requirements (from you)", plan.confirmedRequirements)
            row("Suggested decisions (from the optimizer)", plan.suggestedDecisions)
            row("Constraints", plan.constraints)
            row("Tasks", plan.tasks.map { "\($0.id): \($0.title)\($0.dependsOn.isEmpty ? "" : " ← \($0.dependsOn.joined(separator: ", "))")" })
            row("Success criteria", plan.successCriteria)
            row("Verification", plan.verificationInstructions)
            row("Code references", plan.codeReferences.map { "\($0.path)\($0.symbol.map { " · \($0)" } ?? "") — \($0.reason) [\($0.source.rawValue)]" })
            row("Planned components (not in the codebase yet)", plan.plannedComponents.map { "\($0.name) (\($0.type.rawValue))" })
            if plan.iterationLimit > 0 { row("Iteration limit", ["\(plan.iterationLimit) attempts"]) }
            row("Notices", plan.notices)
            if !plan.selectedTechniques.isEmpty { row("Techniques", [plan.selectedTechniques.map(\.rawValue).joined(separator: " · ")]) }
        }
        .font(Theme.body)
    }

    @ViewBuilder func row(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                FieldLabel(title)
                ForEach(items, id: \.self) { Text($0).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}
