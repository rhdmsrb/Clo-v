import SwiftUI

/// Corner radii. Cards are 24pt; chips and buttons are pills.
enum Radius {
    static let card: CGFloat = 24
    static let tile: CGFloat = 16
    static let small: CGFloat = 12
    static let control: CGFloat = 16
    static let pill: CGFloat = 999
    /// Editorial hero photos: almost square.
    static let hero: CGFloat = 4
}

extension Theme {
    // Older names, kept so existing call sites compile.
    static let cardRadius = Radius.card
    static let tileRadius = Radius.tile
    static let smallRadius = Radius.small
    static let controlRadius = Radius.control
    static let fieldRadius = Radius.control
    static let barRadius = Radius.pill
    static let chipRadius = Radius.pill
    static let avatarRadius = Radius.pill
}
