import SwiftUI

/// Shared optimistic icon toggle behind `LikeButton` and `BookmarkButton`.
/// `perform` receives the new desired value; throwing rolls the UI back.
private struct OptimisticIconToggle: View {
    let onSymbol: String
    let offSymbol: String
    let onTint: Color
    let label: String
    let onValue: String
    let offValue: String
    let identifier: String
    let isOn: Bool
    let count: Int?
    let title: String?
    let perform: (Bool) async throws -> Void

    @State private var state: OptimisticToggle

    init(
        onSymbol: String, offSymbol: String, onTint: Color,
        label: String, onValue: String, offValue: String, identifier: String,
        isOn: Bool, count: Int?, title: String? = nil, perform: @escaping (Bool) async throws -> Void
    ) {
        self.onSymbol = onSymbol
        self.offSymbol = offSymbol
        self.onTint = onTint
        self.label = label
        self.onValue = onValue
        self.offValue = offValue
        self.identifier = identifier
        self.isOn = isOn
        self.count = count
        self.title = title
        self.perform = perform
        _state = State(initialValue: OptimisticToggle(isOn: isOn, count: count))
    }

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 4) {
                Image(systemName: state.isOn ? onSymbol : offSymbol)
                    .symbolEffect(.bounce, value: state.isOn)
                if let title {
                    Text(title).font(Theme.font(.footnote, weight: .semibold)).lineLimit(1)
                }
                if let shown = state.count {
                    Text("\(shown)").font(Theme.font(.footnote, weight: .semibold)).monospacedDigit()
                }
            }
            .foregroundStyle(state.isOn ? onTint : Theme.ink)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(InstantPressStyle())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .onChange(of: isOn) { _, _ in state = state.synced(isOn: isOn, count: count) }
        .onChange(of: count) { _, _ in state = state.synced(isOn: isOn, count: count) }
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(identifier)
    }

    private var accessibilityValue: String {
        let base = state.isOn ? onValue : offValue
        guard let shown = state.count else { return base }
        return "\(base), \(shown)"
    }

    private func tap() {
        guard let next = state.toggled() else { return }
        state = next
        Haptics.impact(.light)
        let desired = next.isOn
        Task { @MainActor in
            do {
                try await perform(desired)
                state = state.succeeded()
            } catch {
                Log.app.error("\(label) toggle failed: \(error.localizedDescription)")
                state = state.rolledBack()
                Haptics.error()
            }
        }
    }
}

struct LikeButton: View {
    let isLiked: Bool
    var count: Int?
    /// Short visible label next to the icon (feed cards); nil for icon-only.
    var title: String?
    var accessibilityIdentifier = "like-button"
    let perform: (Bool) async throws -> Void

    var body: some View {
        OptimisticIconToggle(
            onSymbol: "heart.fill", offSymbol: "heart", onTint: Theme.accentDeep,
            label: "Like", onValue: "Liked", offValue: "Not liked",
            identifier: accessibilityIdentifier, isOn: isLiked, count: count, title: title, perform: perform
        )
    }
}

struct BookmarkButton: View {
    let isBookmarked: Bool
    var accessibilityIdentifier = "bookmark-button"
    let perform: (Bool) async throws -> Void

    var body: some View {
        OptimisticIconToggle(
            onSymbol: "bookmark.fill", offSymbol: "bookmark", onTint: Theme.accentDeep,
            label: "Save", onValue: "Saved", offValue: "Not saved",
            identifier: accessibilityIdentifier, isOn: isBookmarked, count: nil, perform: perform
        )
    }
}

#Preview("Like and Bookmark") {
    HStack {
        LikeButton(isLiked: false, count: 12) { _ in try await Task.sleep(for: .seconds(0.3)) }
        BookmarkButton(isBookmarked: true) { _ in throw CancellationError() }
    }
    .padding()
}
