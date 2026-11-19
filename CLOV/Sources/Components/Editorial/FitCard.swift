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

/// Editorial hero photo: full-bleed, nearly square corners and a bottom gradient. A white
/// tag at the top right shows the time left ("5h"); at the bottom left, the occasion sits in
/// a white box in serif italic above a large bold title.
///
/// `media` replaces the default photo, so a caller can put a carousel (with its own
/// gestures) in the photo slot while the overlays stay the same.
struct FitCard<Media: View>: View {
    let content: FitCardContent
    var aspectRatio: CGFloat = 4.0 / 5.0
    var cornerRadius: CGFloat = Radius.hero
    /// Space under the caption; raise it when something overlaps the photo's foot
    /// (page dots, a row of buttons hanging off the edge).
    var captionBottomInset: CGFloat = Spacing.m
    @ViewBuilder let media: () -> Media

    init(content: FitCardContent, aspectRatio: CGFloat = 4.0 / 5.0, cornerRadius: CGFloat = Radius.hero,
         captionBottomInset: CGFloat = Spacing.m, @ViewBuilder media: @escaping () -> Media) {
        self.content = content
        self.aspectRatio = aspectRatio
        self.cornerRadius = cornerRadius
        self.captionBottomInset = captionBottomInset
        self.media = media
    }

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { media() }
            .overlay { Theme.photoScrim.allowsHitTesting(false) }
            .overlay(alignment: .topTrailing) {
                CountdownBadge(expiresAt: content.expiresAt, style: .boxed).padding(Spacing.sm)
            }
            .overlay(alignment: .bottomLeading) {
                caption
                    .padding([.horizontal, .top], Spacing.m + Spacing.xs)
                    .padding(.bottom, captionBottomInset)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let occasion = content.occasion {
                Text(occasion)
                    .font(Theme.serifTag)
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.white)
            }
            Text(content.title)
                .font(Theme.font(.title, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("fitcard-title")
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

extension FitCard where Media == FitCardPhoto {
    /// Card with the default photo for `content.photoURL`.
    init(content: FitCardContent, aspectRatio: CGFloat = 4.0 / 5.0, cornerRadius: CGFloat = Radius.hero) {
        self.init(content: content, aspectRatio: aspectRatio, cornerRadius: cornerRadius) {
            FitCardPhoto(url: content.photoURL)
        }
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
