import SwiftUI

/// Icon-styled wrapper over the system share sheet — the one sharing
/// affordance used everywhere in the app now, instead of splitting
/// between this (previously: copy-to-clipboard + a checkmark toggle)
/// and `GroupDetailView`'s separate native `ShareLink`. The system sheet
/// already offers "Copy" among its options, so nothing is lost, and
/// Messages/AirDrop/etc. are gained. Use the deployed web vote page when
/// configured, with the app scheme as a working fallback during development.
struct ShareLinkButton: View {
    let fitCheckId: UUID
    var title: String = "Share Fit-Check"
    var summary: String?

    private var shareURL: URL {
        if let base = Bundle.main.object(forInfoDictionaryKey: "CLOVShareBaseURL") as? String,
           let url = URL(string: base), url.scheme == "https", url.host != nil {
            return url.appending(path: "vote/\(fitCheckId.uuidString.lowercased())")
        }
        return URL(string: "clov://vote/\(fitCheckId.uuidString.lowercased())")!
    }

    private var shareText: String {
        if let summary, !summary.isEmpty { return "\(summary)\n\nVote on CLO·V: \(shareURL.absoluteString)" }
        return "Vote on my Fit-Check on CLO·V: \(shareURL.absoluteString)"
    }

    var body: some View {
        ShareLink(item: shareText, subject: Text(title)) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(title)
    }
}
