import SwiftUI

/// What a `FitCard` shows. Plain values, so previews and tests need no network.
struct FitCardContent: Equatable {
    var username: String
    var avatarURL: String?
    var title: String
    /// Short editorial label set in serif italic over the photo ("Date night").
    var occasion: String?
    var tags: [String]
    var expiresAt: Date?
    /// Total votes; nil hides the count (before the viewer has voted).
    var voteCount: Int?
    var photoURL: URL?
}

extension FitCardContent {
    /// Maps a feed row to card content. `revealsVotes` decides whether the total shows.
    init(item: FeedItemDTO, photoIndex: Int, revealsVotes: Bool) {
        let urls = PostCardContent.photoURLs(item.fitCheckPhotos)
        let occasion = item.occasion?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            username: item.profiles?.nickname ?? "Someone",
            avatarURL: item.profiles?.avatarUrl,
            title: PostCardContent.title(votePrompt: item.votePrompt, occasion: nil),
            occasion: (occasion?.isEmpty ?? true) ? nil : occasion,
            tags: PostCardContent.displayTags(item.tags, limit: 3),
            expiresAt: item.expiresAt,
            voteCount: revealsVotes ? item.totalVotes : nil,
            photoURL: urls.indices.contains(photoIndex) ? urls[photoIndex] : urls.first
        )
    }
}

/// Full-bleed fit photo with 24pt corners and a bottom gradient. Over the photo: the
/// author (top left), the countdown (top right), and at the bottom a serif-italic
/// occasion, a bold title, style tags and the vote count.
///
/// `media` replaces the default photo, so a caller can put a carousel (with its own
/// gestures) in the photo slot while the overlays stay the same.
struct FitCard<Media: View>: View {
    let content: FitCardContent
    var aspectRatio: CGFloat = 4.0 / 5.0
    @ViewBuilder let media: () -> Media

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { media() }
            .overlay { Theme.photoScrim.allowsHitTesting(false) }
            .overlay(alignment: .topLeading) { author.padding(Spacing.sm).allowsHitTesting(false) }
            .overlay(alignment: .topTrailing) { CountdownBadge(expiresAt: content.expiresAt).padding(Spacing.sm) }
            .overlay(alignment: .bottomLeading) { caption.padding(Spacing.m).allowsHitTesting(false) }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .environment(\.colorScheme, .dark) // overlays sit on a dark scrim in both modes
    }

    private var author: some View {
        HStack(spacing: Spacing.s) {
            AvatarView(url: content.avatarURL, nickname: content.username, size: 28)
            Text(content.username)
                .font(Theme.font(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.leading, Spacing.xs)
        .padding(.trailing, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(.black.opacity(0.28), in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Posted by \(content.username)")
    }

    private var caption: some View {
        HStack(alignment: .bottom, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xs + 2) {
                if let occasion = content.occasion {
                    Text(occasion)
                        .font(Theme.serifLabel)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
                Text(content.title)
                    .font(Theme.font(.title2, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                StyleTagRow(tags: content.tags, style: .onPhoto)
            }
            Spacer(minLength: 0)
            if let votes = content.voteCount { voteCount(votes) }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func voteCount(_ votes: Int) -> some View {
        VStack(spacing: 0) {
            Text("\(votes)")
                .font(Theme.font(.title3, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(votes == 1 ? "vote" : "votes")
                .font(Theme.micro)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(votes == 1 ? "1 vote" : "\(votes) votes")
        .accessibilityIdentifier("fitcard-vote-count")
    }
}

extension FitCard where Media == FitCardPhoto {
    /// Card with the default photo for `content.photoURL`.
    init(content: FitCardContent, aspectRatio: CGFloat = 4.0 / 5.0) {
        self.content = content
        self.aspectRatio = aspectRatio
        self.media = { FitCardPhoto(url: content.photoURL) }
    }
}

/// The default photo layer: a cached remote image, or a soft placeholder when the
/// URL is missing or fails (so previews need no network).
struct FitCardPhoto: View {
    let url: URL?

    var body: some View {
        if let url {
            CachedImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        LinearGradient(colors: [Color(white: 0.78), Color(white: 0.62)], startPoint: .top, endPoint: .bottom)
            .overlay {
                Image(systemName: "figure.stand")
                    .font(.system(size: 120, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .accessibilityHidden(true)
    }
}

#Preview("Fit card") {
    ScrollView {
        VStack(spacing: Spacing.l) {
            FitCard(content: FitCardContent(
                username: "maya.chen", avatarURL: nil, title: "Which one for the gallery opening?",
                occasion: "Date night", tags: ["#minimal", "#monochrome"],
                expiresAt: .now.addingTimeInterval(5 * 3_600 + 120), voteCount: 128, photoURL: nil))
            FitCard(content: FitCardContent(
                username: "junwearsthings", avatarURL: nil, title: "Campus fit check",
                occasion: nil, tags: ["#streetwear"],
                expiresAt: .now.addingTimeInterval(40 * 60), voteCount: nil, photoURL: nil))
        }
        .padding(Spacing.m)
    }
    .background(Theme.background)
}
