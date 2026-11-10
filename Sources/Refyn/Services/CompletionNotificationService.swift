import UserNotifications

@MainActor
final class CompletionNotificationService {
    // XCTest and snapshot processes can construct AppModel without an application bundle.
    // Do not ask UserNotifications for its process-wide center until the user opts in.
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func sendCompletion() {
        let content = UNMutableNotificationContent()
        content.title = "Your prompt is ready"
        content.body = "Optimization is complete. Open Refyn to view the result."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "refyn.optimization.complete.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                NSLog("Refyn could not schedule the completion notification: %@", error.localizedDescription)
            }
        }
    }
}
