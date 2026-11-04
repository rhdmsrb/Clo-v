import Foundation

/// Custom URL schemes can be opened by any app or web page, so a
/// `clov://auth-callback` link is only honoured while a password reset that
/// this device started is still outstanding. Without this, a crafted link
/// could sign the user into an attacker's account.
struct AuthCallbackGate {
    static let shared = AuthCallbackGate()
    /// Supabase recovery links expire after an hour by default.
    static let validity: TimeInterval = 60 * 60

    private let defaults: UserDefaults
    private let now: () -> Date
    private let key = "clov.pendingPasswordResetAt"

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func markResetRequested() {
        defaults.set(now().timeIntervalSince1970, forKey: key)
    }

    /// Returns true at most once per requested reset, within the validity window.
    func consume() -> Bool {
        defer { defaults.removeObject(forKey: key) }
        guard let requestedAt = defaults.object(forKey: key) as? TimeInterval else { return false }
        let age = now().timeIntervalSince1970 - requestedAt
        return age >= 0 && age <= Self.validity
    }
}
