import UIKit

/// Thin wrapper over UIKit's feedback generators, for haptics fired
/// imperatively right at the moment of a state change — e.g. just
/// before a screen dismisses, where a declarative `.sensoryFeedback`
/// trigger wouldn't stay mounted long enough to actually play.
///
/// For feedback tied to a value that changes while the view stays on
/// screen (a vote landing, a tab switching, a chip toggling), prefer
/// SwiftUI's own `.sensoryFeedback(_:trigger:)` modifier directly
/// instead of calling into this type.
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
