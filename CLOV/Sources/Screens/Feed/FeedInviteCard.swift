import SwiftUI

/// Ends a thin feed: a Fit-Check needs voters, so this asks the viewer to bring friends in.
/// "Invite friends" shares a message with the viewer's CLO·V ID; "Find friends" opens search.
struct FeedInviteCard: View {
    let onFindFriends: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var accountCode: String?

    private static let padding: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Better with friends", systemImage: "person.2.fill")
                .font(Theme.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Your looks get votes faster when your friends are here. Invite them, or find people you know.")
                .font(Theme.body)
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(alignment: .leading, spacing: 10) { buttons }
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed-invite-card")
        .task { await loadAccountCode() }
    }

    @ViewBuilder
    private var buttons: some View {
        ShareLink(item: FeedInvite.message(accountCode: accountCode)) {
            Label("Invite friends", systemImage: "square.and.arrow.up")
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.accentForeground)
                .padding(.horizontal, 16)
                .frame(minHeight: Theme.minTapSize)
                .background(Theme.accent, in: Capsule(style: .continuous))
        }
        .accessibilityIdentifier("feed-invite-share")
        Button(action: onFindFriends) {
            Label("Find friends", systemImage: "magnifyingglass")
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.accentDeep)
                .padding(.horizontal, 16)
                .frame(minHeight: Theme.minTapSize)
                .overlay(Capsule(style: .continuous).stroke(Theme.accentDeep, lineWidth: 1))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("feed-invite-find")
    }

    /// The signed-in profile doesn't carry the CLO·V ID; without it the message still invites.
    private func loadAccountCode() async {
        let profiles = await Log.attempt("Load own CLO·V ID") {
            try await API.fetchProfiles(ids: [appState.userId])
        }
        accountCode = profiles?.first?.accountCode
    }
}
