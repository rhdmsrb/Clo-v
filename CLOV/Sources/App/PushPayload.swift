import Foundation

/// The custom keys the server puts next to `aps` in a push, used to open the
/// Fit-Check a notification is about.
struct PushPayload: Equatable {
    let fitCheckId: UUID
    let type: String?

    init?(userInfo: [AnyHashable: Any]) {
        guard let rawId = userInfo["fitCheckId"] as? String,
              let fitCheckId = UUID(uuidString: rawId)
        else { return nil }
        self.fitCheckId = fitCheckId
        self.type = userInfo["type"] as? String
    }
}
