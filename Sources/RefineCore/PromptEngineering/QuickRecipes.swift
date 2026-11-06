import Foundation

/// Instant, model-free improvements for small requests: sensible steps, acceptance criteria and checks for the
/// kind of change asked for. General practice only; nothing here claims anything about the user's codebase.
enum QuickRecipes {
    struct Recipe {
        var tasks: [PlanTask]
        var successCriteria: [String]
        var verification: [String]
        var suggestions: [String]
    }

    static func recipe(for analysis: RequestAnalysis) -> Recipe? {
        let text = analysis.text.lowercased()
        func has(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }

        if has(#"\brename\b"#) {
            return Recipe(
                tasks: [PlanTask(id: "t1", title: "Find every usage", detail: "Search code, strings, tests, docs and config for the old name before editing."),
                        PlanTask(id: "t2", title: "Rename consistently", detail: "Update the definition and every usage without changing behavior.", dependsOn: ["t1"]),
                        PlanTask(id: "t3", title: "Verify", detail: "Build and run the existing tests.", dependsOn: ["t2"])],
                successCriteria: ["No stale references to the old name remain unless intentionally kept.", "Behavior is unchanged."],
                verification: ["Search the project for the old name and review every remaining match.", "Run the build and the existing tests."],
                suggestions: ["Prefer the language's rename tooling over plain search-and-replace."])
        }
        if has(#"\b(remove|delete|drop|get rid of)\b"#) {
            return Recipe(
                tasks: [PlanTask(id: "t1", title: "Find what depends on it", detail: "List every usage and everything that would break before deleting."),
                        PlanTask(id: "t2", title: "Remove it and clean up", detail: "Delete the code and any dead references, imports and tests.", dependsOn: ["t1"]),
                        PlanTask(id: "t3", title: "Verify", detail: "Build and run the existing tests.", dependsOn: ["t2"])],
                successCriteria: ["Nothing references the removed code.", "Unrelated behavior is unchanged."],
                verification: ["Run the build and the existing tests.", "Search for leftover references."],
                suggestions: ["If something still depends on it, report that instead of removing it silently."])
        }
        // Only small, self-contained UI tweaks. A feature such as "add dark mode" is not one of them.
        if has(#"\b(tooltip|label|icon|button|placeholder|caption|copy|padding|margin|spacing|font size|tint)\b"#), !has(#"\b(dark mode|theme|redesign|onboarding|flow)\b"#) {
            return Recipe(
                tasks: [PlanTask(id: "t1", title: "Locate the component", detail: "Find where this element is defined and how similar ones are built."),
                        PlanTask(id: "t2", title: "Make the change", detail: "Follow the existing components and design tokens.", dependsOn: ["t1"]),
                        PlanTask(id: "t3", title: "Check it visually", detail: "Confirm the result and its states.", dependsOn: ["t2"])],
                successCriteria: ["The change appears where requested.", "Nothing else in the UI changes."],
                verification: ["Check the element in each relevant state (hover, focus, disabled) and in light and dark appearance if supported.", "Run the build and the existing tests."],
                suggestions: ["Reuse the existing component or design tokens instead of adding new styles.", "Keep the element reachable and labeled for keyboard and screen-reader users."])
        }
        return nil
    }
}
