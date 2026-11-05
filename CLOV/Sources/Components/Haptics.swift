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
@MainActor
enum Haptics {
    // Generators are kept alive and re-armed after every use. A throwaway
    // generator has to spin up the Taptic Engine on first use, which is
    // what made taps feel late.
    private static let notification = UINotificationFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)

    /// Call when a screen with tappable feedback appears so the first tap is instant.
    static func prepare() {
        notification.prepare()
        light.prepare()
        medium.prepare()
    }

    static func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    static func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = generator(for: style)
        generator.impactOccurred()
        generator.prepare()
    }

    private static func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .light: light
        case .medium: medium
        case .heavy: heavy
        case .soft: soft
        case .rigid: rigid
        @unknown default: medium
        }
    }
}
