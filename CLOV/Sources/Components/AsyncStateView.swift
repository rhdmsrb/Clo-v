import SwiftUI

/// Keep previously loaded content visible when a refresh fails.
struct AsyncStateView<Content: View>: View {
    var isLoading: Bool
    var error: String?
    var isEmpty: Bool = false
    var emptyText: String = ""
    var topPadding: CGFloat = 40
    var hasLoaded = false
    var retry: (() async -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        if isLoading && !hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, topPadding)
        } else {
            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    if let retry {
                        Button("Try again") { Task { await retry() } }
                            .disabled(isLoading)
                    }
                }
            }
            if hasLoaded || error == nil {
                if isEmpty {
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, topPadding)
                } else {
                    content()
                }
            }
        }
    }
}
