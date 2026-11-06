import SwiftUI
import UIKit

/// A branded, shareable picture of a Fit-Check's result, laid out like a page
/// from a magazine rather than a dashboard: hairline rules, one large serif
/// question, serif percentages and a single accent for the leading look.
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
    /// 9:16, so the picture fits a story without cropping.
    private static let minHeight: CGFloat = 640
    private static let paper = Color(red: 0.988, green: 0.965, blue: 0.973)
    private static let ink = Color(red: 0.227, green: 0.125, blue: 0.161)
    private static let rose = Color(red: 0.894, green: 0.569, blue: 0.651)
    private static let roseDeep = Color(red: 0.447, green: 0.271, blue: 0.353)
    private static let fallbackPrompt = "Which look wins?"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            rule.padding(.top, 12)
            Text(promptText)
                .font(Theme.editorialFont(size: 30, relativeTo: .title))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
            Spacer(minLength: 24)
            if showsPhotos { photoGrid } else { barRows }
            Spacer(minLength: 24)
            rule
            Text("Settle it on CLO·V")
                .font(Theme.font(.caption2, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Self.roseDeep)
                .padding(.top, 12)
        }
        .padding(24)
        .frame(width: Self.cardWidth, alignment: .leading)
        .frame(minHeight: Self.minHeight, alignment: .top)
        .foregroundStyle(Self.ink)
        .background(Self.paper)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
    }

    private var promptText: String {
        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? Self.fallbackPrompt : trimmed
    }

    private var rule: some View {
        Rectangle().fill(Self.ink.opacity(0.35)).frame(height: 1)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CLO·V").font(Theme.editorialFont(size: 22, relativeTo: .title3))
            Spacer()
            Text("\(totalVotes) \(totalVotes == 1 ? "vote" : "votes")")
                .font(Theme.font(.caption2, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Self.roseDeep)
        }
    }

    private func label(_ entry: Entry) -> String { "Look \(entry.position)" }

    // MARK: Photos (creator)

    private var photoGrid: some View {
        let ratio: CGFloat = entries.count > 2 ? 1 : 3.0 / 4.0
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 14) {
            ForEach(entries) { entry in tile(entry, ratio: ratio) }
        }
    }

    private func tile(_ entry: Entry, ratio: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .overlay {
                    if let image = entry.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Self.ink.opacity(0.08)
                    }
                }
                .clipped()
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label(entry))
                        .font(Theme.font(.caption2, weight: .bold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Self.ink.opacity(0.6))
                    if entry.isLeading {
                        Text("Winning")
                            .font(Theme.font(.caption2, weight: .bold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(Self.roseDeep)
                    }
                }
                Spacer(minLength: 4)
                Text("\(entry.percent)%")
                    .font(Theme.editorialFont(size: 30, relativeTo: .title))
                    .foregroundStyle(entry.isLeading ? Self.ink : Self.ink.opacity(0.55))
            }
        }
    }

    // MARK: Bars (voter: no photos leave the app)

    private var barRows: some View {
        VStack(spacing: 22) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label(entry))
                                .font(Theme.font(.caption2, weight: .bold))
                                .tracking(1.2)
                                .textCase(.uppercase)
                                .foregroundStyle(Self.ink.opacity(0.6))
                            if entry.isLeading || entry.isMine {
                                Text(entry.isLeading && entry.isMine ? "Winning · my pick"
                                     : entry.isLeading ? "Winning" : "My pick")
                                    .font(Theme.font(.caption2, weight: .bold))
                                    .tracking(1.2)
                                    .textCase(.uppercase)
                                    .foregroundStyle(Self.roseDeep)
                            }
                        }
                        Spacer(minLength: 8)
                        Text("\(entry.percent)%")
                            .font(Theme.editorialFont(size: 44, relativeTo: .largeTitle))
                            .foregroundStyle(entry.isLeading ? Self.ink : Self.ink.opacity(0.55))
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Self.ink.opacity(0.12)
                            (entry.isLeading ? Self.rose : Self.ink.opacity(0.4))
                                .frame(width: proxy.size.width * CGFloat(max(0, min(100, entry.percent))) / 100)
                        }
                    }
                    .frame(height: 4)
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
