import SwiftUI

/// Row of look thumbnails under a hero photo. Tapping one selects that look; the
/// selected thumbnail gets an ink outline. Missing or failed images show a soft gray tile.
struct ThumbnailStrip: View {
    let urls: [URL?]
    @Binding var selectedIndex: Int
    var accessibilityPrefix = "Look"

    private static let height: CGFloat = 64
    private static let aspect: CGFloat = 3.0 / 4.0

    var body: some View {
        HStack(spacing: Spacing.s) {
            ForEach(urls.indices, id: \.self) { index in
                thumbnail(index)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Looks")
    }

    private func thumbnail(_ index: Int) -> some View {
        let isSelected = index == selectedIndex
        return Button {
            Haptics.selection()
            selectedIndex = index
        } label: {
            image(urls[index])
                .frame(width: Self.height * Self.aspect, height: Self.height)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .strokeBorder(isSelected ? Theme.ink : Color.clear, lineWidth: 2)
                }
                .opacity(isSelected ? 1 : 0.75)
                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityPrefix) \(index + 1)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("thumbnail-\(index)")
        .motionSafeAnimation(Theme.quick, value: isSelected)
    }

    @ViewBuilder
    private func image(_ url: URL?) -> some View {
        if let url {
            CachedImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Theme.muted
                }
            }
        } else {
            Theme.muted
        }
    }
}

#Preview("Thumbnail strip") {
    struct Demo: View {
        @State private var index = 1
        var body: some View {
            ThumbnailStrip(urls: [nil, nil, nil, nil], selectedIndex: $index)
                .padding(Spacing.m)
                .background(Theme.background)
        }
    }
    return Demo()
}
