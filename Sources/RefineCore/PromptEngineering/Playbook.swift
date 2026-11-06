import Foundation

/// Domain depth added to a rough request: what to investigate, what "good" looks like, examples and
/// pitfalls. This is general engineering knowledge, not facts about the user's codebase, so it is always
/// presented as a suggested bar the agent may adjust and never as a requirement the user stated.
public struct PlaybookGuidance: Codable, Hashable, Sendable {
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

    public init(topic: String, direction: String? = nil, investigate: [String], goodLooksLike: [String], examples: [String], avoid: [String]) {
        self.topic = topic; self.direction = direction; self.investigate = investigate; self.goodLooksLike = goodLooksLike; self.examples = examples; self.avoid = avoid
    }
}

public enum Playbook {
    /// Playbooks help vague requests. A request that already spells out its details is left alone.
    static let maxComplexity = 4

    public static func match(_ analysis: RequestAnalysis, context: RetrievedContext) -> PlaybookGuidance? {
        guard analysis.complexity <= maxComplexity else { return nil }
        let text = analysis.text.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }

        let feel = ["smooth", "slow", "fast", "snappy", "gentle", "fluid", "premium", "natural", "graceful", "quick"]
        let movement = ["open", "clos", "expand", "collapse", "slide", "fade", "appear", "morph", "reveal"]
        if has(["animation", "animat", "transition", "easing", "jank", "stutter", "flicker", "laggy open", "feels slow to open", "spring"])
            || (has(feel) && has(movement)) {
            return motion(context, request: text)
        }
        if has(["slow", "laggy", "lag ", "freeze", "freezes", "hangs", "takes forever", "performance", "latency", "memory usage", "speed up"]) {
            return performance
        }
        if has(["ugly", "looks bad", "looks off", "spacing", "alignment", "typography", "font", "color", "contrast", "layout", "design", "polish", "dark mode"]) {
            return visual
        }
        if has(["bug", "broken", "crash", "doesn't work", "not working", "fails", "failing", "error", "regression"]) {
            return bug
        }
        return nil
    }

    // MARK: Playbooks

    enum Pace { case verySlow, slow, standard, fast }

    /// Reads the speed the user asked for, so the suggested numbers move with their intent instead of against it.
    static func pace(in text: String) -> (Pace, String?) {
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        let intensifier = has(["very ", "extremely", "really ", "super ", "much "])
        var feel: [String] = []
        for (word, label) in [("smooth", "smooth"), ("premium", "premium"), ("graceful", "graceful"), ("gentle", "gentle"), ("fluid", "fluid"), ("natural", "natural"), ("snappy", "snappy")] where text.contains(word) { feel.append(label) }
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
        switch pace {
        case .verySlow, .slow:
            let (open, close) = pace == .verySlow ? ("800–1200 ms", "900–1300 ms") : ("500–800 ms", "600–900 ms")
            good = [
                "Opening: expand from the compact state to the full panel over roughly \(open); closing: contract back over roughly \(close). A long duration is the goal here, so do not shorten it to hide problems.",
                "Curve: a soft ease-in-out with gentle acceleration and deceleration, with no abrupt start, stop or sudden change in velocity. A hard ease-out at this length reads as lag, not elegance.",
                "Responsive start: even though the whole motion is long, the first visible movement begins within a frame or two of the trigger, so the interface never feels like it ignored the input.",
                "Morphing: the compact and expanded states are one continuous shape. Width, height and corner radius animate together, with no stepping between sizes.",
                "Content: icons and text fade and slide gently into place as the panel expands (starting part-way through, not at the start), and fade out before the panel finishes closing.",
                "Fluidity: hold 60–120 fps where the display supports it, with no flicker, snapping, layout jumps or visible intermediate glitches.",
                "Interruptible: reversing mid-animation continues from the current visual state instead of jumping to the start or end.",
                "Accessible: with Reduce Motion enabled, replace the movement with a short cross-fade or an instant change.",
            ]
            examples = [
                "Good: the panel grows over about \(pace == .verySlow ? "900" : "600") ms with a soft ease-in-out, content begins fading in at about 40% of the way, and closing takes slightly longer than opening.",
                "Good: hovering or clicking starts movement immediately; the slowness is in the motion itself, not in a delay before it begins.",
                "Bad: nothing happens for a few hundred milliseconds and then the panel moves, which feels like lag.",
                "Bad: the panel changes size in distinct steps, or the content is fully visible while the shape is still growing.",
            ]
        case .fast:
            good = [
                "Duration: an open or expand transition of roughly 120–200 ms, and closing a little quicker, so it feels immediate without being a jump cut.",
                "Curve: ease-out when appearing and ease-in when leaving, or a well-damped spring with no visible overshoot.",
                "Content appears with the container rather than trailing noticeably behind it.",
                "Fluidity: no dropped frames at 60–120 fps, no flicker or layout jumps.",
                "Interruptible: reversing mid-animation continues from the current visual state.",
                "Accessible: with Reduce Motion enabled, use an instant change or a very short cross-fade.",
            ]
            examples = [
                "Good: the panel opens in about 150 ms with an ease-out curve and closes in about 120 ms.",
                "Bad: a fast animation that drops frames; speed does not matter if it stutters.",
            ]
        case .standard:
            good = [
                "Duration: an open or expand transition usually feels right around 200–350 ms; closing is typically faster (150–250 ms). Much longer reads as sluggish, much shorter as abrupt.",
                "Curve: decelerate into the final state (ease-out) when something appears and accelerate out (ease-in) when it leaves, or use a well-damped spring with little or no overshoot.",
                "One coordinated motion: the container's shape leads and its content follows a beat later (about 30–80 ms stagger) rather than appearing before the container has grown.",
                "Smooth: no dropped frames at 60 fps (120 fps on ProMotion displays), no layout jumps, no clipped or flickering content.",
                "Interruptible: reversing mid-animation continues from the current visual state instead of snapping to the start or end.",
                "Accessible: with Reduce Motion enabled, replace movement with a short cross-fade or an instant change.",
            ]
            examples = [
                "Good: the panel grows from its collapsed size over about 250 ms with an ease-out curve, its content fades in during the last ~120 ms, and closing takes about 180 ms.",
                "Good: with Reduce Motion on, the panel cross-fades in about 100 ms and nothing moves.",
                "Bad: the content is already fully visible while the container is still growing.",
                "Bad: the shape overshoots its final size and then snaps back, or a quick open-close-open leaves it stuck at the wrong size.",
            ]
        }
        let stack = (context.frameworks + context.languages).joined(separator: " ").lowercased()
        if stack.contains("swiftui") || stack.contains("swift") || stack.contains("appkit") {
            good.append("Apple platforms: prefer animating opacity and transforms with a value-scoped animation (for example `.animation(_, value:)`) over animating layout every frame; for AppKit panels, drive frame changes with `NSAnimationContext` or Core Animation instead of manual timers.")
        }
        if stack.contains("react") || stack.contains("css") || stack.contains("vue") || stack.contains("svelte") || stack.contains("typescript") || stack.contains("javascript") {
            good.append("Web: animate `transform` and `opacity` (compositor-friendly) instead of `width`, `height`, `top` or `left`, and respect `prefers-reduced-motion`.")
        }
        return PlaybookGuidance(
            topic: "Animation and motion quality",
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
                "Treat the durations and curves above as starting points and keep the product's existing motion language where it has one.",
            ])
    }

    static let performance = PlaybookGuidance(
        topic: "Performance",
        investigate: [
            "State what is slow and when: the exact action, the starting state, and roughly how slow it feels (a number from a stopwatch beats \"slow\").",
            "Measure before changing anything: use a profiler or timing logs on a realistic data size and write down the baseline.",
            "Find the hot path: what runs on the critical path, what runs more often than it should, and what blocks the main thread or the UI.",
            "Check the usual causes: repeated work inside loops or renders, unbounded data loading, missing caching or batching, sequential work that could be parallel, and large synchronous I/O.",
        ],
        goodLooksLike: [
            "A measurable target agreed up front, for example \"under 200 ms for this action on a typical dataset\", replacing the vague \"fast\".",
            "Before and after numbers for the same scenario, reported in the final summary.",
            "Behavior unchanged: the existing tests pass and the output for the same inputs is identical.",
            "The fix addresses the measured hot spot, not the first slow-looking line.",
        ],
        examples: [
            "Good: \"Profiling shows 70% of the time in re-parsing the config on every call. Caching the parsed value cuts the action from 1.4 s to 0.2 s; tests unchanged.\"",
            "Bad: adding a cache or a background thread without measuring, then reporting that it \"should be faster\".",
        ],
        avoid: [
            "Do not optimize without a baseline measurement.",
            "Do not trade correctness for speed: no stale data, dropped work or changed behavior unless asked.",
            "Do not rewrite large areas when a targeted change at the hot spot is enough.",
        ])

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
            "Trace the failing path to the root cause. Check recent changes to that area (`git log` and `git blame`) for a regression.",
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
