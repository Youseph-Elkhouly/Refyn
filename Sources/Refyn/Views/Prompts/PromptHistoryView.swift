import RefineCore
import SwiftUI

struct PromptHistoryView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var results: [PromptPlan] = []
    @State private var selected: PromptPlan.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.sm) {
                SearchField(text: $query, placeholder: "Search previous prompts")
                Text("Recent").font(Theme.caption).foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 10).padding(.vertical, 10)

            if results.isEmpty {
                EmptyState(symbol: "clock.arrow.circlepath", title: query.isEmpty ? "No prompt history yet" : "No matches",
                           detail: query.isEmpty ? "Optimized prompts will appear here." : nil)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(results) { plan in row(plan) }
                    }
                    .padding(.horizontal, 6).padding(.bottom, 10)
                }
            }
        }
        .task(id: query) { await model.reloadPromptHistory(matching: query); results = model.promptHistory }
        .onChange(of: model.promptHistory) { results = model.promptHistory }
    }

    private func row(_ plan: PromptPlan) -> some View {
        let isSelected = selected == plan.id
        return ListRow(selected: isSelected) { selected = isSelected ? nil : plan.id } content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Theme.Space.sm) {
                    Text(plan.originalPrompt).font(Theme.body).lineLimit(isSelected ? 4 : 2)
                    Spacer(minLength: 0)
                    Text(plan.createdAt.formatted(.relative(presentation: .named)))
                        .font(Theme.caption).foregroundStyle(Theme.textMuted).fixedSize()
                }
                Text(plan.optimizedPrompt.replacingOccurrences(of: "\n", with: " "))
                    .font(Theme.mono).foregroundStyle(Theme.textSecondary).lineLimit(isSelected ? 4 : 2)
                if isSelected {
                    HStack(spacing: Theme.Space.sm) {
                        RButton(title: "View result", symbol: "arrow.up.forward", kind: .primary) { model.openHistoryResult(plan) }
                        RButton(title: "Reuse request", symbol: "square.and.pencil") { model.reuseHistoryRequest(plan) }
                        RButton(title: "Copy optimized", symbol: "doc.on.doc") { model.copy(plan.optimizedPrompt) }
                        Spacer(minLength: 0)
                        Chip(text: plan.taskType.rawValue)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .motion(Theme.Motion.base, value: isSelected)
    }
}
