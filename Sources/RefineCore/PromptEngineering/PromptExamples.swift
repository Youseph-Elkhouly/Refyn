import Foundation

/// Compact worked examples for the local model. Exactly one is sent per request, chosen by task type, so the
/// token cost stays small. Every example is an illustration only: the model is told never to reuse its details.
enum PromptExamples {
    struct Example {
        let name: String
        let request: String
        let json: String
    }

    static let vague = Example(
        name: "vague request to an actionable prompt",
        request: "add dark mode",
        json: #"""
        {"objective":"Add a dark appearance that users can switch to, without changing how the existing light appearance looks.","confirmedRequirements":["Support a dark appearance"],"suggestedDecisions":["Follow the system appearance by default and offer a manual override","Route colors through the existing theme or design tokens instead of hard-coded values","Check text and control contrast in both appearances"],"tasks":[{"id":"t1","title":"Find where colors and theme are defined","detail":"Locate the shared theme or token layer."},{"id":"t2","title":"Add the dark palette and the switch","detail":"Define dark token values and apply the chosen appearance.","dependsOn":["t1"]},{"id":"t3","title":"Check every screen in both appearances","detail":"Fix hard-coded colors.","dependsOn":["t2"]}],"successCriteria":["The dark appearance can be selected and stays selected","The light appearance looks unchanged"],"verificationSteps":["Run the existing tests and build","Visually check the main screens in both appearances"]}
        """#)

    static let complexFeature = Example(
        name: "complex feature to a structured implementation prompt",
        request: "let admins invite people by email to a workspace, invites expire after 7 days, keep the current settings page layout",
        json: #"""
        {"objective":"Let workspace admins invite people by email, with invitations that expire after 7 days, while keeping the current settings page layout.","confirmedRequirements":["Admins can invite a person by email","An invitation expires after 7 days"],"suggestedDecisions":["Store each invitation with its email, workspace, inviter and expiry time","Make accepting an expired or already-used invitation fail with a clear message","Allow an admin to resend or revoke a pending invitation","Reject an invitation for an email that is already a member"],"tasks":[{"id":"t1","title":"Model invitations","detail":"Store invitations with expiry and status."},{"id":"t2","title":"Add the invite and accept flow","detail":"Create, email, accept and expire invitations.","dependsOn":["t1"]},{"id":"t3","title":"Add the admin entry point","detail":"Expose invitations in the existing settings page.","dependsOn":["t2"]},{"id":"t4","title":"Cover the edge cases with tests","detail":"Test expiry, reuse, duplicates and non-admins.","dependsOn":["t2"]}],"successCriteria":["An admin can send an invitation and the recipient can accept it","An invitation older than 7 days cannot be accepted","The settings page layout is unchanged"],"verificationSteps":["Run the existing tests and the new invitation tests","Manually send and accept an invitation, then try an expired one"]}
        """#)

    static let bug = Example(
        name: "bug report to diagnostic and corrective instructions",
        request: "saving a profile sometimes loses the new avatar",
        json: #"""
        {"objective":"Find and fix why saving a profile sometimes loses the newly chosen avatar, so the saved profile always keeps it.","confirmedRequirements":["The new avatar must be kept when a profile is saved"],"suggestedDecisions":["Look first at the order of the avatar upload and the profile save, and at what happens if one finishes first","Check whether the save sends a stale copy of the profile that overwrites the avatar"],"tasks":[{"id":"t1","title":"Reproduce the loss","detail":"Find the smallest steps that lose the avatar."},{"id":"t2","title":"Find the cause","detail":"Trace the avatar to where it is dropped.","dependsOn":["t1"]},{"id":"t3","title":"Fix it and add a regression test","detail":"Make the smallest fix and add a failing-first test.","dependsOn":["t2"]}],"successCriteria":["Saving a profile with a new avatar always keeps the avatar","The regression test fails before the fix and passes after it"],"verificationSteps":["Repeat the reproduction steps several times after the fix","Run the existing tests to confirm nothing else changed"]}
        """#)

    static let ui = Example(
        name: "UI request to precise visual and motion guidance",
        request: "make the sidebar feel more premium, keep the current icons",
        json: #"""
        {"objective":"Refine the sidebar so it feels more premium through spacing, typography and subtle motion, keeping the current icons.","confirmedRequirements":["Keep the current icons"],"suggestedDecisions":["Use consistent spacing from one scale and align icons and labels on a shared baseline","Use a clearer type hierarchy: one weight for items, one lighter style for secondary text","Add a subtle hover and selection state, for example a soft background change over about 150 ms","Keep motion calm: ease-in-out, no bounce, and respect Reduce Motion","Use only the existing design tokens, with no new colors"],"tasks":[{"id":"t1","title":"Review the current sidebar","detail":"Note spacing, hierarchy and state inconsistencies."},{"id":"t2","title":"Apply the refinements","detail":"Adjust spacing, type and states using existing tokens.","dependsOn":["t1"]}],"successCriteria":["The icons are unchanged","Spacing and alignment are consistent across all items","Hover and selected states are clearly distinguishable"],"verificationSteps":["Compare before and after screenshots in light and dark appearance","Check keyboard focus and Reduce Motion"]}
        """#)

    static let constrained = Example(
        name: "request with strict constraints that must stay unchanged",
        request: "make search faster but don't change the result order or the public API",
        json: #"""
        {"objective":"Make search faster without changing the order of results or the public API.","confirmedRequirements":["Search must be faster"],"suggestedDecisions":["Measure the current search time on a realistic data size first, and use that as the baseline","Look for repeated work, unbounded loading and missing indexes before changing anything"],"tasks":[{"id":"t1","title":"Measure the baseline","detail":"Time one search scenario first."},{"id":"t2","title":"Find the hot spot","detail":"Profile the search path.","dependsOn":["t1"]},{"id":"t3","title":"Optimize and re-measure","detail":"Change only what is measured, then re-time.","dependsOn":["t2"]}],"successCriteria":["The same search is measurably faster than the baseline","Results come back in the same order as before","The public API is unchanged"],"verificationSteps":["Compare before and after timings for the same scenario","Run the existing tests, including any that check result order"]}
        """#)

    /// A tiny example for the compact prompt. It shows the style and size of a good answer in about 120 tokens.
    static let mini = Example(
        name: "small change",
        request: "add a loading spinner to the save button",
        json: #"""
        {"objective":"Show a loading spinner on the save button while a save is in progress.","confirmedRequirements":["Add a loading spinner to the save button"],"suggestedDecisions":["Disable the button while saving to prevent double submits","Use the app's existing spinner component"],"tasks":[{"id":"t1","title":"Find the save button and its save handler"},{"id":"t2","title":"Show the spinner while the save runs","dependsOn":["t1"]}],"successCriteria":["The spinner appears during a save and disappears when it finishes"],"verificationSteps":["Trigger a save and watch the button, then run the existing tests"]}
        """#)

    /// Picks the example closest to the request. One example keeps the prompt short.
    static func select(taskType: TaskType, hasConstraints: Bool, complexity: Int) -> Example {
        switch taskType {
        case .bugfix: bug
        case .ui: ui
        case .performance: constrained
        default:
            if hasConstraints { constrained }
            else if complexity >= 4 { complexFeature }
            else { vague }
        }
    }
}
