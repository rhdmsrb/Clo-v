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

    /// nil hides the button: see `ShareURL` for why there is no custom-scheme fallback in release.
    private var shareURL: URL? { ShareURL.make(fitCheckId: fitCheckId) }

    private func shareText(for url: URL) -> String {
        if let summary, !summary.isEmpty { return "\(summary)\n\nVote on CLO·V: \(url.absoluteString)" }
        return "Vote on my Fit-Check on CLO·V: \(url.absoluteString)"
    }

    var body: some View {
        if let shareURL {
            ShareLink(item: shareText(for: shareURL), subject: Text(title)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(title)
        }
    }
}
