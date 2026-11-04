import SwiftUI

/// Section title with an optional trailing text action ("See all").
struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Theme.label)
                        .foregroundStyle(Theme.accentDeep)
                        .frame(minHeight: Theme.minTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    SectionHeader(title: "Trending", actionTitle: "See all") {}
        .padding()
        .background(Theme.background)
}
