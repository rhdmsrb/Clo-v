import SwiftUI

/// 8pt spacing grid (with a 4pt half step for tight icon/label gaps).
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let sm: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    /// Side margin for page content; matches the HIG compact-width margin.
    static let pageGutter: CGFloat = 16
}

extension Theme {
    /// Minimum comfortable tap target (HIG).
    static let minTapSize: CGFloat = 44
    /// Height of primary pill CTAs.
    static let ctaHeight: CGFloat = 52
}
