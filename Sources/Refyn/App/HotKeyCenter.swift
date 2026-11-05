import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts via Carbon hot keys, which need no Accessibility permission and report
/// both key-down and key-up (for push-to-talk).
@MainActor
final class HotKeyCenter {
    enum Action: UInt32 { case toggle = 1, pushToTalk = 2 }

    var onPress: (Action) -> Void = { _ in }
    var onRelease: (Action) -> Void = { _ in }
    private var refs: [Action: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    init() {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated {
                guard let action = Action(rawValue: id.id) else { return }
                pressed ? center.onPress(action) : center.onRelease(action)
            }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    @discardableResult
    func register(_ action: Action, _ shortcut: Shortcut) -> Bool {
        unregister(action)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x52464E45), id: action.rawValue) // 'RFNE'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[action] = ref
        return true
    }

    func unregister(_ action: Action) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
    }

    func unregisterAll() {
        for action in refs.keys { unregister(action) }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}
