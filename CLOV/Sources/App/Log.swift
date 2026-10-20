import Foundation
import os

/// Structured logging for failures that are handled but shouldn't vanish.
/// Interpolated values default to private in release logs.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.clov.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let push = Logger(subsystem: subsystem, category: "push")
    static let storage = Logger(subsystem: subsystem, category: "storage")

    /// For best-effort work whose failure must not block the screen but
    /// shouldn't vanish either: returns nil on failure after logging it.
    /// Cancellation is expected and not logged.
    static func attempt<T>(_ what: String, _ operation: () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch is CancellationError {
            return nil
        } catch {
            app.error("\(what) failed: \(error.localizedDescription)")
            return nil
        }
    }
}
