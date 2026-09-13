import Foundation

enum InviteCode {
    // No ambiguous chars (0/O, 1/I) — mirrors the web prototype's
    // src/lib/invite-code.ts.
    private static let charset = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func generate(length: Int = 6) -> String {
        String((0..<length).compactMap { _ in charset.randomElement() })
    }
}
