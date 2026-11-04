import SwiftUI
import UIKit

/// A branded, shareable picture of a Fit-Check's result.
///
/// Uses fixed (non-adaptive) colors and a pinned type size so the picture
/// looks the same in light and dark mode. It never shows nicknames or other
/// account details, only the prompt, the looks and their vote share.
struct ResultShareCard: View {
    struct Entry: Identifiable {
        let id: UUID
        let position: Int
        let percent: Int
        let image: UIImage?
        let isLeading: Bool
        let isMine: Bool
    }

    let prompt: String?
    let totalVotes: Int
    let entries: [Entry]
    let showsPhotos: Bool

    private static let cardWidth: CGFloat = 360
    /// Keeps every bar starting at the same x regardless of the digits shown.
    private static let badgeWidth: CGFloat = 30
    private static let ink = Color(red: 0.227, green: 0.125, blue: 0.161)
    private static let pink = Color(red: 0.894, green: 0.569, blue: 0.651)
    private static let fallbackPrompt = "Which look wins?"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text(promptText)
                .font(Theme.editorialFont(size: 26, relativeTo: .title2))
                .fixedSize(horizontal: false, vertical: true)
            if showsPhotos { photoGrid } else { barRows }
            Text("Cast your vote on CLO·V")
                .font(Theme.font(.caption, weight: .bold))
                .tracking(0.8)
        }
        .padding(20)
        .frame(width: Self.cardWidth, alignment: .leading)
        .foregroundStyle(Self.ink)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
    }

    private var promptText: String {
        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? Self.fallbackPrompt : trimmed
    }

    private var header: some View {
        HStack {
            Text("CLO·V").font(Theme.font(.headline, weight: .heavy))
            Spacer()
            Text("\(totalVotes) \(totalVotes == 1 ? "VOTE" : "VOTES")")
                .font(Theme.font(.caption2, weight: .black))
                .tracking(1.2)
        }
    }

    // MARK: Photos (creator)

    private var photoGrid: some View {
        let ratio: CGFloat = entries.count > 2 ? 1 : 3.0 / 4.0
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(entries) { entry in tile(entry, ratio: ratio) }
        }
    }

    private func tile(_ entry: Entry, ratio: CGFloat) -> some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                if let image = entry.image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Self.ink.opacity(0.1)
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) { badge(String(format: "%02d", entry.position)) }
            .overlay(alignment: .bottom) { percentFooter(entry) }
            .overlay(Rectangle().stroke(Self.ink, lineWidth: entry.isLeading ? 3 : 1))
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(.caption2, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Self.ink)
    }

    private func percentFooter(_ entry: Entry) -> some View {
        HStack(spacing: 4) {
            Text("\(entry.percent)%").font(Theme.font(.headline, weight: .black))
            if entry.isLeading { Image(systemName: "star.fill").font(.caption2) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(Self.ink)
    }

    // MARK: Bars (voter: no photos leave the app)

    private var barRows: some View {
        VStack(spacing: 8) {
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    badge(String(format: "%02d", entry.position))
                        .frame(width: Self.badgeWidth)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Self.ink.opacity(0.08)
                            Self.pink.frame(width: proxy.size.width * CGFloat(entry.percent) / 100)
                        }
                    }
                    .frame(height: 28)
                    Text("\(entry.percent)%")
                        .font(Theme.font(.headline, weight: .black))
                        .frame(minWidth: 48, alignment: .trailing)
                }
            }
        }
    }
}

/// Lazily rendered PNG for `ShareLink`: photos are fetched and the card is drawn
/// only when the share sheet actually asks for the data. ImageRenderer output
/// is a fresh bitmap, so no EXIF/location metadata from any source photo remains.
struct ResultShareImage: Transferable {
    struct Row: Sendable {
        let id: UUID
        let position: Int
        let percent: Int
        let imageURL: URL?
        let isLeading: Bool
        let isMine: Bool
    }

    let prompt: String?
    let totalVotes: Int
    let rows: [Row]
    /// Only the creator's own photos leave the app; voters share bars only.
    let showsPhotos: Bool

    private static let renderScale: CGFloat = 3

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try await item.renderPNG()
        }
    }

    @MainActor
    func renderPNG() async throws -> Data {
        var entries: [ResultShareCard.Entry] = []
        for row in rows {
            var image: UIImage?
            if showsPhotos, let url = row.imageURL { image = await ImageCache.shared.image(for: url) }
            entries.append(.init(id: row.id, position: row.position, percent: row.percent,
                                 image: image, isLeading: row.isLeading, isMine: row.isMine))
        }
        let renderer = ImageRenderer(content: ResultShareCard(prompt: prompt, totalVotes: totalVotes,
                                                              entries: entries, showsPhotos: showsPhotos))
        renderer.scale = Self.renderScale
        guard let data = renderer.uiImage?.pngData() else { throw URLError(.cannotDecodeContentData) }
        return data
    }
}
