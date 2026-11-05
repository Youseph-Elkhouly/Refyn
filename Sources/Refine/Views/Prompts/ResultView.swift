import RefineCore
import SwiftUI

struct ResultView: View {
    @Bindable var model: AppModel
    enum Tab: String, CaseIterable { case optimized = "Optimized", original = "Original", plan = "Plan" }
    @State private var tab: Tab = .optimized
    @State private var stage = 0

    var body: some View {
        if let plan = model.plan {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                    Spacer()
                    Chip(text: plan.provider == "local" ? "local draft" : plan.provider, color: plan.provider == "local" ? Theme.warning : Theme.accent)
                    Chip(text: plan.taskType.rawValue)
                    if !plan.validation.passed {
                        Chip(text: plan.validation.repaired ? "original quoted" : "check intent", color: Theme.warning)
                            .help(plan.validation.missingTerms.isEmpty ? "The model reported it may have changed your intent." :
                                    "These terms from your request were missing, so the original request is quoted: \(plan.validation.missingTerms.joined(separator: ", "))")
                    }
                }
                if tab == .optimized && !plan.chainedPrompts.isEmpty {
                    Picker("", selection: $stage) {
                        Text("Full prompt").tag(-1)
                        ForEach(plan.chainedPrompts.indices, id: \.self) { Text("Step \($0 + 1)").tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                ScrollView {
                    Group {
                        switch tab {
                        case .optimized: Text(currentText(plan)).font(Theme.mono)
                        case .original: Text(plan.originalPrompt).font(.system(size: 13.5))
                        case .plan: PlanDetails(plan: plan)
                        }
                    }
                    .foregroundStyle(Theme.text.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))

                Text(plan.selectedTechniques.map(\.rawValue).joined(separator: " · "))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.tertiary).lineLimit(2)

                HStack(spacing: 8) {
                    Button { model.copy(currentText(plan)) } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                    Picker("Agent", selection: $model.agentID) {
                        ForEach(AgentRegistry.all, id: \.id) { Text($0.displayName).tag($0.id) }
                    }
                    .labelsHidden().frame(width: 120).help("Where you'll paste the prompt")
                    Button { Task { await model.savePrompt() } } label: { Label("Save", systemImage: "bookmark") }.buttonStyle(PillButtonStyle())
                    Button { model.visualize() } label: { Label("Visualize", systemImage: "point.3.connected.trianglepath.dotted") }.buttonStyle(PillButtonStyle())
                    Button { Task { await model.startReview() } } label: { Label("Review Changes", systemImage: "checklist") }
                        .buttonStyle(PillButtonStyle())
                        .disabled(model.execution == nil)
                        .help(model.execution == nil ? "Copy the prompt first; Refine records the repository state at that moment." : "Inspect what changed since you copied the prompt.")
                    Spacer()
                    Button("Edit") { model.input = plan.originalPrompt; model.route = .compose }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .onChange(of: plan.id) { stage = -1; tab = .optimized }
            .onAppear { stage = -1 }
        } else {
            ContentUnavailableView("No prompt yet", systemImage: "sparkles", description: Text("Write a request and choose Optimize."))
        }
    }

    func currentText(_ plan: PromptPlan) -> String {
        if tab == .optimized, plan.chainedPrompts.indices.contains(stage) { return plan.chainedPrompts[stage] }
        return tab == .original ? plan.originalPrompt : plan.optimizedPrompt
    }
}

struct PlanDetails: View {
    let plan: PromptPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Intent", [plan.intent])
            row("Confirmed requirements (from you)", plan.confirmedRequirements)
            row("Suggested decisions (from the optimizer)", plan.suggestedDecisions)
            row("Constraints", plan.constraints)
            row("Tasks", plan.tasks.map { "\($0.id): \($0.title)\($0.dependsOn.isEmpty ? "" : " ← \($0.dependsOn.joined(separator: ", "))")" })
            row("Success criteria", plan.successCriteria)
            row("Verification", plan.verificationInstructions)
            row("Missing information", plan.missingInformation)
            row("Code references", plan.codeReferences.map { "\($0.path)\($0.symbol.map { " · \($0)" } ?? "") — \($0.reason) [\($0.source.rawValue)]" })
            row("Planned components (not in the codebase yet)", plan.plannedComponents.map { "\($0.name) (\($0.type.rawValue))" })
            if plan.iterationLimit > 0 { row("Iteration limit", ["\(plan.iterationLimit) attempts"]) }
            row("Notices", plan.notices)
        }
        .font(.system(size: 12.5))
    }

    @ViewBuilder func row(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: title)
                ForEach(items, id: \.self) { Text("• \($0)") }
            }
        }
    }
}
