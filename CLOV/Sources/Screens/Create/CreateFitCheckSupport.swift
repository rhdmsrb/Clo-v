import SwiftUI
import PhotosUI

struct PhotoSlotState: Identifiable {
    let id = UUID()
    var item: PhotosPickerItem?
    var image: UIImage?
}

enum FitCheckAudience: String, CaseIterable, Identifiable {
    case everyone = "public"
    case friends
    case group
    case onlyMe = "private"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyone: "Everyone"
        case .friends: "Friends"
        case .group: "A group"
        case .onlyMe: "Only me"
        }
    }
    var symbol: String {
        switch self {
        case .everyone: "globe"
        case .friends: "person.2"
        case .group: "person.3"
        case .onlyMe: "lock"
        }
    }
    var description: String {
        switch self {
        case .everyone: "Anyone on CLO·V can see and vote."
        case .friends: "Only people you’ve accepted as friends can see and vote."
        case .group: "Only members of the selected group can see and vote."
        case .onlyMe: "Only you can see this Fit-Check. It won’t appear in feeds."
        }
    }
}

/// Not in the original CLAUDE.md scope; added on request.
enum VotingDuration: CaseIterable, Identifiable {
    case oneHour, sixHours, oneDay

    var id: Self { self }
    var label: String {
        switch self {
        case .oneHour: "1 hour"
        case .sixHours: "6 hours"
        case .oneDay: "24 hours"
        }
    }
    var seconds: TimeInterval {
        switch self {
        case .oneHour: 3600
        case .sixHours: 6 * 3600
        case .oneDay: 24 * 3600
        }
    }
}

struct PhotoSlotView: View {
    @Binding var state: PhotoSlotState
    let label: String

    @State private var pickError: String?

    private static let tileRadius: CGFloat = 18

    var body: some View {
        VStack(spacing: 6) {
            picker
            if let pickError {
                Text(pickError)
                    .font(.caption2)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var picker: some View {
        PhotosPicker(selection: $state.item, matching: .images) {
            AspectFitTile(cornerRadius: Self.tileRadius, shadow: state.image != nil) {
                if state.image == nil {
                    RoundedRectangle(cornerRadius: Self.tileRadius)
                        .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .background(Theme.card.clipShape(RoundedRectangle(cornerRadius: Self.tileRadius)))
                }
                if let image = state.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .accessibilityHidden(true)
                } else {
                    Text("+ \(label)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.mutedForeground)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(state.image == nil ? "Add \(label)" : "Change \(label)")
        .accessibilityHint(state.image == nil ? "Opens your photo library" : "Replaces the selected photo")
        .onChange(of: state.item) { _, newItem in
            Task {
                pickError = nil
                guard let newItem else { return }
                do {
                    state.image = try await newItem.loadImage()
                } catch {
                    Log.app.error("Photo pick failed: \(error.localizedDescription)")
                    pickError = error.localizedDescription
                }
            }
        }
    }
}

struct WardrobePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [WardrobeItem]
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (WardrobeItem) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(Theme.danger)
                    }
                    grid
                }
                .padding(20)
            }
            .background(Theme.background)
            .overlay {
                if isLoading {
                    ProgressView("Loading photo…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                }
            }
            .navigationTitle("Choose from Wardrobe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 14) {
            ForEach(items) { item in
                Button { onSelect(item) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        RemoteImage(url: item.imageUrl, label: Self.displayName(for: item))
                            .aspectRatio(3.0 / 4.0, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(Self.displayName(for: item).uppercased())
                            .font(Theme.micro)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
    }

    private static func displayName(for item: WardrobeItem) -> String {
        if let name = item.name, !name.isEmpty { return name }
        return item.subcategory ?? item.category
    }
}
