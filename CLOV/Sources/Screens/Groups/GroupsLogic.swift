import CoreGraphics
import Foundation

/// Decides when the Group Feed member row hides (scroll down) or returns (scroll up).
/// Offsets beyond the content bounds (rubber-band bounce) are clamped so they never
/// read as a direction change.
enum AvatarRowScrollRule {
    struct Result: Equatable {
        /// `nil` means "no change".
        let shouldShow: Bool?
        /// The offset to remember as the new reference point.
        let anchor: CGFloat
    }

    static let threshold: CGFloat = 8

    /// - Parameter offset: the content's minY in the scroll space (0 at top, negative when scrolled).
    static func evaluate(offset: CGFloat, lastOffset: CGFloat,
                         contentHeight: CGFloat, viewportHeight: CGFloat) -> Result {
        let maxScroll = max(0, contentHeight - viewportHeight)
        let clamped = min(0, max(offset, -maxScroll))
        if clamped >= 0 { return Result(shouldShow: true, anchor: 0) }
        let delta = clamped - lastOffset
        if delta < -threshold { return Result(shouldShow: false, anchor: clamped) }
        if delta > threshold { return Result(shouldShow: true, anchor: clamped) }
        return Result(shouldShow: nil, anchor: lastOffset)
    }
}

/// Group name rules (server enforces 2-40 characters after trimming).
enum GroupNameValidator {
    static let range = 2...40
    static let message = "Group name must be 2-40 characters."

    static func validated(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard range.contains(trimmed.count) else { throw APIError.message(message) }
        return trimmed
    }
}

/// Typed invite-code cleanup. Generated codes never contain 0, O, 1 or I
/// (see `InviteCode`), so those characters are almost certainly typos.
enum InviteCodeInput {
    static let ambiguousCharacters: Set<Character> = ["0", "O", "1", "I"]
    static let hint = "Codes never use 0, O, 1 or I. Check for look-alike letters or numbers."

    static func normalize(_ raw: String) -> String {
        String(raw.filter { !$0.isWhitespace }).uppercased()
    }

    static func hasAmbiguousCharacters(_ raw: String) -> Bool {
        normalize(raw).contains { ambiguousCharacters.contains($0) }
    }
}
