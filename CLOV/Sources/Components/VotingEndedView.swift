import SwiftUI

/// Shown instead of the photos/results once a Fit-Check's timer runs
/// out — not in the original CLAUDE.md scope; added on request. Per
/// spec this hides results completely (stricter than a manually
/// "Terminated" post, which stays read-only-visible), so this
/// deliberately does NOT take photos/vote counts as input — there's
/// nothing to reveal here, even to the creator, even via a shared link.
struct VotingEndedView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 28))
                .foregroundStyle(Theme.mutedForeground)
                .accessibilityHidden(true)
            Text("Voting has ended")
                .font(.system(.subheadline, design: .default).weight(.bold))
            Text("The photos and results for this Fit-Check are no longer visible.")
                .font(.caption)
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background(Theme.muted)
        .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
    }
}
