import Foundation
import os

/// Structured logging for failures that are handled but shouldn't vanish.
/// Interpolated values default to private in release logs.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.clov.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let push = Logger(subsystem: subsystem, category: "push")
    static let storage = Logger(subsystem: subsystem, category: "storage")
}
