import Foundation

/// Domain depth added to a rough request: what to investigate, what "good" looks like, examples and
/// pitfalls. This is general engineering knowledge, not facts about the user's codebase, so it is always
/// presented as a suggested bar the agent may adjust and never as a requirement the user stated.
public struct PlaybookGuidance: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case diagnose, create }
    public var kind: Kind
    public var topic: String
    /// The feel the user asked for in their own words (for example "very slow and smooth"), when they gave one.
    public var direction: String?
    /// Steps to establish what is actually wrong before changing anything.
    public var investigate: [String]
    /// A suggested quality bar.
    public var goodLooksLike: [String]
    /// Concrete good and bad examples.
    public var examples: [String]
    public var avoid: [String]

    public init(topic: String, kind: Kind = .diagnose, direction: String? = nil, investigate: [String], goodLooksLike: [String], examples: [String], avoid: [String]) {
        self.topic = topic; self.kind = kind; self.direction = direction; self.investigate = investigate; self.goodLooksLike = goodLooksLike; self.examples = examples; self.avoid = avoid
    }
}

public enum Playbook {
    /// Playbooks help vague requests. A request that already spells out its details is left alone.
    static let maxComplexity = 4

    public static func match(_ analysis: RequestAnalysis, context: RetrievedContext) -> PlaybookGuidance? {
        guard analysis.complexity <= maxComplexity else { return nil }
        let text = analysis.text.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        let complaints = ["broken", "janky", "laggy", "stutter", "fix", "bug"]
        let isCreation = analysis.taskType == .feature || has(["add", "implement", "create", "build", "introduce", "support", "new"])
        let creationRequest = isCreation && !has(complaints)
        let feel = ["smooth", "slow", "fast", "snappy", "gentle", "fluid", "premium", "natural", "graceful", "quick", "cool", "playful", "subtle", "bold", "minimal", "flashy", "elegant"]
        let movement = ["open", "clos", "expand", "collapse", "slide", "fade", "appear", "morph", "reveal"]
        let mentionsInteractiveEffect = has(["hover", "cursor", "pointer", "interactive"])
            && has(["effect", "feedback", "trail", "style"])
        let mentionsMotion = has(["animation", "animat", "transition", "easing", "jank", "stutter", "flicker", "laggy open", "feels slow to open", "spring"])
            || mentionsInteractiveEffect
            || (has(feel) && has(movement))
        if mentionsMotion && creationRequest { return motionCreate(context, request: text) }
        if mentionsMotion {
            return motion(context, request: text)
        }
        if !creationRequest,
           has(["slow", "laggy", "lag ", "freeze", "freezes", "hangs", "takes forever", "performance", "latency", "memory usage", "speed up"]) {
            return performance(for: analysis)
        }
        // Creating something new is a feature, not a complaint about something existing.
        if !creationRequest, has(["ugly", "looks bad", "looks off", "spacing", "alignment", "typography", "contrast", "polish", "premium", "cluttered"]) {
            return visual
        }
        if !creationRequest, has(["bug", "broken", "crash", "doesn't work", "not working", "fails", "failing", "error", "regression"]) {
            return bug
        }
        if creationRequest && has(["spinner", "modal", "cursor", "button", "menu", "page", "website", "interface", "visual"]) {
            return featureCreate(analysis)
        }
        return underspecified(analysis)
    }

    /// "make authentication better": the goal is open-ended, so the useful step is to establish what exists and what is wrong with it.
    /// Nothing here names a technology, a protocol or a fix; those are decisions for the user or findings for the agent.
    static func underspecified(_ analysis: RequestAnalysis) -> PlaybookGuidance? {
        guard analysis.taskType == .other, analysis.keyTerms.isEmpty, analysis.constraints.isEmpty,
              let m = analysis.text.captures(#"(?i)^(?:please\s+)?(?:make|improve|enhance|upgrade|modernize|polish|clean up|fix up)\s+(?:the\s+|our\s+|my\s+)?([a-z][a-z \-/]{2,40}?)(?:\s+(?:better|nicer|cleaner|more\s+\w+|less\s+\w+))?\s*[.!]?$"#),
              !m[1].isEmpty, m[1].split(separator: " ").count <= 4 else { return nil }
        var subject = m[1].trimmingCharacters(in: .whitespaces)
        for filler in [" better", " nicer", " cleaner"] where subject.hasSuffix(filler) { subject = String(subject.dropLast(filler.count)) }
        return PlaybookGuidance(
            topic: "an open-ended improvement to \(subject)",
            investigate: [
                "Find the code that implements \(subject) and describe how it works today: files, entry points and what it depends on.",
                "List concrete problems you can observe in it, such as bugs, missing error handling, unclear flows or gaps in tests, each with a file reference.",
                "Check the existing tests and documentation for behavior that other code or users rely on.",
            ],
            goodLooksLike: [
                "Every proposed change names a specific observed problem and where it is.",
                "Changes are ordered by impact and small enough to review one at a time.",
                "Existing behavior is preserved unless a change is justified by something you observed.",
            ],
            examples: [],
            avoid: [
                "Introducing protocols, libraries or services the project does not already use.",
                "Rewriting parts that work and have no observed problem.",
                "Guessing what the request means by an improvement; report what you found and offer options instead.",
            ])
    }

    // MARK: Playbooks

    static func featureCreate(_ analysis: RequestAnalysis) -> PlaybookGuidance {
        PlaybookGuidance(topic: "Feature implementation", kind: .create,
            investigate: ["Find where the requested feature belongs and check for existing patterns or similar behavior."],
            goodLooksLike: ["Implement the requested behavior and preserve the user's concrete details.", "Follow existing product patterns; state any important choice the request leaves open."],
            examples: [], avoid: ["Do not add unrelated functionality or assume requirements the user did not give."])
    }

    enum Pace { case verySlow, slow, standard, fast }

    /// Reads the speed the user asked for, so the suggested numbers move with their intent instead of against it.
    static func pace(in text: String) -> (Pace, String?) {
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        let intensifier = has(["very ", "extremely", "really ", "super ", "much "])
        var feel: [String] = []
        for (word, label) in [("smooth", "smooth"), ("premium", "premium"), ("graceful", "graceful"), ("gentle", "gentle"), ("fluid", "fluid"), ("natural", "natural"), ("snappy", "snappy"), ("cool", "cool"), ("playful", "playful"), ("subtle", "subtle"), ("bold", "bold"), ("minimal", "minimal"), ("flashy", "flashy"), ("elegant", "elegant")] where text.contains(word) { feel.append(label) }
        if has(["slow", "relaxed", "leisurely", "unhurried"]) {
            return (intensifier ? .verySlow : .slow, ((intensifier ? ["very slow"] : ["slow"]) + feel).joined(separator: ", "))
        }
        if has(["fast", "quick", "snappy", "instant", "faster"]) { return (.fast, (["fast"] + feel.filter { $0 != "snappy" }).joined(separator: ", ")) }
        return (.standard, feel.isEmpty ? nil : feel.joined(separator: ", "))
    }

    static func motion(_ context: RetrievedContext, request: String = "") -> PlaybookGuidance {
        let (pace, direction) = pace(in: request)
        var good: [String]
        var examples: [String]
        let pacing = pace == .fast ? "Keep the requested fast response without abrupt visual jumps."
            : (pace == .slow || pace == .verySlow) ? "Preserve the requested slow, graceful pacing with a soft ease-in-out."
            : "Inspect timing and choose pacing based on the reported symptom and existing interaction."
        good = [
            pacing,
            "Use continuous motion with controlled acceleration and deceleration; consider ease-out where appropriate.",
            "Content should appear naturally within the transition rather than popping in before its container.",
            "Check frame pacing on supported displays; profile observed hitches before changing timings.",
            "Respect Reduce Motion with a short fade or an immediate state change."
        ]
        if ["open", "clos", "expand", "collapse", "resize"].contains(where: request.contains) {
            good.insert("Width, height and corner radius should change together without layout jumps.", at: 2)
            good.insert("Interrupted or reversed transitions should continue from the current visible state.", at: 3)
        }
        examples = ["Good: the requested transition reaches its intended state without snapping.",
                    "Bad: content jumps or an interrupted transition finishes in the wrong state."]
        let stack = (context.frameworks + context.languages).joined(separator: " ").lowercased()
        if stack.contains("swiftui") || stack.contains("swift") || stack.contains("appkit") {
            good.append("Apple platforms: prefer animating opacity and transforms with a value-scoped animation (for example `.animation(_, value:)`) over animating layout every frame; for AppKit panels, drive frame changes with `NSAnimationContext` or Core Animation instead of manual timers.")
        }
        if stack.contains("react") || stack.contains("css") || stack.contains("vue") || stack.contains("svelte") || stack.contains("typescript") || stack.contains("javascript") {
            good.append("Web: animate `transform` and `opacity` (compositor-friendly) instead of `width`, `height`, `top` or `left`, and respect `prefers-reduced-motion`.")
        }
        return PlaybookGuidance(
            topic: "Animation and motion quality",
            kind: .diagnose,
            direction: direction,
            investigate: [
                "Reproduce it and record the screen, stepping through frames (QuickTime, or slow-motion if available). Write down exactly which moment looks wrong instead of fixing a general impression.",
                "Find where the animation is triggered and list what actually animates: which properties, the duration, the curve, and whether several animations compete on the same property.",
                "Name the symptom: too slow or too fast, abrupt start or stop, dropped frames, content popping in early or late, layout jump, overshoot or bounce, or a bad reversal when interrupted mid-flight.",
                "If frames are dropping, profile before changing timings: look for main-thread work during the animation, layout recalculation every frame, and expensive shadows, blurs or offscreen rendering.",
            ],
            goodLooksLike: good,
            examples: examples,
            avoid: [
                "Do not hide jank by only changing the duration; find what is dropping frames.",
                "Do not remove the animation entirely unless asked.",
                "Do not stack extra animations on a property that is already animated; replace the existing one.",
                "Keep the existing motion language and use measurements before selecting new timing values.",
            ])
    }

    static func motionCreate(_ context: RetrievedContext, request: String) -> PlaybookGuidance {
        let (_, direction) = pace(in: request)
        let stack = (context.frameworks + context.languages).joined(separator: " ").lowercased()
        let interactiveEffect = request.range(of: #"(?i)\b(?:hover|cursor|pointer|interactive)\w*\b"#, options: .regularExpression) != nil
        var good = [
            "Honor the requested visual theme and feel\(direction.map { ": \($0)" } ?? "") and make the effect visible against the site's backgrounds.",
            "Keep the effect from blocking clicks, selection or text input."
        ]
        if interactiveEffect {
            good += [
                "Provide :focus-visible feedback equivalent to the hover effect for keyboard users.",
                "Respect prefers-reduced-motion.",
                "Touch devices do not have hover; provide tap feedback or no hover-only effect.",
                "Use the site's existing palette and accent colors.",
                "Use a transition with an explicit duration and easing chosen to fit the existing interaction style."
            ]
        }
        if stack.contains("react") || stack.contains("css") || stack.contains("vue") || stack.contains("svelte") || stack.contains("typescript") || stack.contains("javascript") {
            good += ["On web, animate transform and opacity rather than layout properties.", "Respect prefers-reduced-motion; for pointer-driven effects, disable them on touch or coarse-pointer devices.", "Use one requestAnimationFrame loop at most and cancel it when the effect is inactive."]
        }
        return PlaybookGuidance(topic: "Animation and motion design", kind: .create, direction: direction,
            investigate: [
                "Locate where the feature belongs and identify the stack and existing visual language (palette, typography and interaction patterns).",
                "Check whether a similar animation or effect already exists so the new effect can fit the site without duplicating behavior."
            ], goodLooksLike: good, examples: [], avoid: ["Do not alter unrelated page behavior or invent site-specific design tokens."])
    }

    static func performance(for analysis: RequestAnalysis) -> PlaybookGuidance {
        let text = analysis.searchText
        let database = text.range(of: #"(?i)\b(database|db|sql|query|queries)\b"#, options: .regularExpression) != nil
        let concurrent = text.range(of: #"(?i)\b(concurren|simultaneous|multiple users|under load|timeout|time out)\w*\b"#, options: .regularExpression) != nil
        var investigate = [
            "Reproduce the reported workload and record a baseline before changing code.",
            "Profile the critical path and identify the measured bottleneck before choosing a fix.",
        ]
        if database && concurrent {
            investigate.append("For concurrent database timeouts, check query plans and access patterns, connection-pool waits, lock contention, timeout evidence, and CPU, memory or I/O saturation as candidates; change only the cause supported by measurements.")
        } else if database {
            investigate.append("Inspect query plans, query timings and access patterns; treat bottlenecks as hypotheses until diagnostics support them.")
        }
        return PlaybookGuidance(
            topic: "Performance",
            investigate: investigate,
            goodLooksLike: [
                "Compare the same representative workload before and after and report measured results without inventing a target.",
                "Preserve the API and observable behavior unless the request explicitly allows a change.",
            ],
            examples: [],
            avoid: ["Do not select an optimization before profiling identifies a bottleneck."])
    }

    static let visual = PlaybookGuidance(
        topic: "Visual design quality",
        investigate: [
            "Look at the current result and capture a screenshot. Write down what specifically looks wrong: spacing, alignment, hierarchy, contrast, size, or inconsistency with the rest of the app.",
            "Find the existing design tokens and shared components (colors, spacing, typography, radii) and use them instead of introducing new values.",
            "Check every state of the element: default, hover, pressed, focused, disabled, loading, empty, error, and light and dark appearance if the app supports both.",
        ],
        goodLooksLike: [
            "Consistent: spacing and sizes come from the existing scale, and similar elements look and behave alike.",
            "A clear hierarchy: the primary action or content stands out and secondary items recede.",
            "Readable: body text meets roughly 4.5:1 contrast, and interactive targets are comfortably large.",
            "Aligned: edges and baselines line up, and nothing is clipped, truncated or crowded at the smallest and largest supported sizes.",
            "Accessible: keyboard focus is visible, controls have labels, and the result still works with larger text or Reduce Motion where relevant.",
        ],
        examples: [
            "Good: the same 8 pt spacing step between related controls, one primary button per view, and a visible focus ring on every control.",
            "Bad: one-off padding values, three slightly different grays for the same role, or a label that truncates at a larger text size.",
        ],
        avoid: [
            "Do not introduce new colors, fonts or spacing values outside the existing design tokens unless asked.",
            "Do not redesign unrelated screens while fixing one element.",
        ])

    static let bug = PlaybookGuidance(
        topic: "Bug investigation",
        investigate: [
            "Write down the exact reproduction steps, the expected result, and the actual result, including any error message or log line.",
            "Reproduce it first, ideally with the smallest failing case or a failing test, before changing code.",
            "Trace the failing path to the root cause. Check the recent history of that area for a regression.",
            "Check whether the same cause affects other call sites before deciding the size of the fix.",
        ],
        goodLooksLike: [
            "The root cause is identified and explained, not just the symptom hidden.",
            "A regression test fails before the fix and passes after it.",
            "The change is the smallest that fixes the cause, with existing tests still passing.",
            "The final report states the cause, the fix, and how it was verified.",
        ],
        examples: [
            "Good report: \"Cause: the retry counter was reset on every call. Fix: move it outside the loop. Test: added a case that fails on the old code. Ran the full suite.\"",
            "Bad: wrapping the failing call in a broad try/catch so the error disappears.",
        ],
        avoid: [
            "Do not swallow errors or add broad catch-alls to make a failure go away.",
            "Do not weaken or delete a test to make it pass.",
            "Do not fix more than the reported problem without saying so.",
        ])
}
