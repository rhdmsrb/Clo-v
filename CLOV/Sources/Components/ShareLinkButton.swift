import SwiftUI

/// Icon-styled wrapper over the system share sheet — the one sharing
/// affordance used everywhere in the app now, instead of splitting
/// between this (previously: copy-to-clipboard + a checkmark toggle)
/// and `GroupDetailView`'s separate native `ShareLink`. The system sheet
/// already offers "Copy" among its options, so nothing is lost, and
/// Messages/AirDrop/etc. are gained. The `clov://` scheme deep-links
/// straight back into this app on a device that has it installed (see
/// `.onOpenURL` in CLOVApp); the `https://` line is a stand-in for
/// wherever this ships publicly, since no real domain is set up yet for
/// this prototype.
struct ShareLinkButton: View {
    let fitCheckId: UUID

    private var shareText: String {
        "https://clov.app/vote/\(fitCheckId.uuidString) (clov://vote/\(fitCheckId.uuidString))"
    }

    var body: some View {
        ShareLink(item: shareText) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel("Share")
    }
}
