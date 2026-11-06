import Foundation
import RefineCore

enum VoiceMode: String, CaseIterable, Identifiable {
    case transcribe = "Transcribe"
    case clean = "Clean"
    case optimize = "Optimize"
    var id: String { rawValue }
    var summary: String {
        switch self {
        case .transcribe: "Insert exactly what was heard."
        case .clean: "Remove filler words, keep every technical term."
        case .optimize: "Clean, then build a local prompt draft. Nothing is sent to a model until you choose Optimize."
        }
    }
}

/// UserDefaults-backed settings. Model inference and speech stay on this Mac.
enum Preferences {
    static var defaults: UserDefaults { .standard }

    static var iterationLimit: Int {
        get { defaults.object(forKey: "iterationLimit") as? Int ?? 3 }
        set { defaults.set(newValue, forKey: "iterationLimit") }
    }
    static var askForMissingInformation: Bool {
        get { defaults.object(forKey: "askForMissingInformation") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "askForMissingInformation") }
    }
    static var mode: PromptMode {
        get { defaults.string(forKey: "promptMode").flatMap(PromptMode.init(rawValue:)) ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "promptMode") }
    }
    static var customTechniques: Set<PromptTechnique> {
        get { Set((defaults.stringArray(forKey: "customTechniques") ?? []).compactMap(PromptTechnique.init(rawValue:))) }
        set { defaults.set(newValue.map(\.rawValue), forKey: "customTechniques") }
    }
    static var voiceMode: VoiceMode {
        get { defaults.string(forKey: "voiceMode").flatMap(VoiceMode.init(rawValue:)) ?? .clean }
        set { defaults.set(newValue.rawValue, forKey: "voiceMode") }
    }
    static var speechModel: SpeechModel {
        get { defaults.string(forKey: "speechModel").flatMap(SpeechModel.init(rawValue:)) ?? .base }
        set { defaults.set(newValue.rawValue, forKey: "speechModel") }
    }
    static var collapseOnFocusLoss: Bool {
        get { defaults.object(forKey: "collapseOnFocusLoss") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "collapseOnFocusLoss") }
    }
    static var nodePath: String {
        get { defaults.string(forKey: "nodePath") ?? "" }
        set { defaults.set(newValue, forKey: "nodePath") }
    }
    static var agentID: String {
        get { defaults.string(forKey: "agentID") ?? "claude-code" }
        set { defaults.set(newValue, forKey: "agentID") }
    }
    static var lastWorkspaceID: UUID? {
        get { defaults.string(forKey: "lastWorkspaceID").flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: "lastWorkspaceID") }
    }
    static var toggleShortcut: Shortcut {
        get { defaults.shortcut("toggleShortcut") ?? .defaultToggle }
        set { defaults.setShortcut(newValue, for: "toggleShortcut") }
    }
    static var pushToTalkShortcut: Shortcut {
        get { defaults.shortcut("pushToTalkShortcut") ?? .defaultPushToTalk }
        set { defaults.setShortcut(newValue, for: "pushToTalkShortcut") }
    }

}
