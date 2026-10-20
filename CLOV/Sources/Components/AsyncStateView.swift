import SwiftUI

/// Keep previously loaded content visible when a refresh fails.
///
/// Error and empty states can be customised with an icon, title and action;
/// all of the extra parameters are optional so existing call sites keep working.
struct AsyncStateView<Content: View>: View {
    var isLoading: Bool
    var error: String?
    var isEmpty: Bool = false
    var emptyText: String = ""
    var topPadding: CGFloat = 40
    var hasLoaded = false
    var retry: (() async -> Void)? = nil
    var emptyIcon: String? = nil
    var emptyTitle: String? = nil
    var emptyActionTitle: String? = nil
    var emptyAction: (() -> Void)? = nil
    var errorIcon: String? = nil
    var errorTitle: String? = nil
    var retryTitle: String = "Try again"
    var skeleton: SkeletonStyle = .spinner
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if isLoading && !hasLoaded {
                SkeletonView(style: skeleton)
                    .frame(maxWidth: .infinity)
                    .padding(.top, skeleton == .spinner ? topPadding : 0)
            } else if let error, !hasLoaded {
                // Nothing to show yet: the error takes the place of content.
                errorBlock(error, centered: true)
            } else {
                if let error { errorBlock(error, centered: false) }
                if isEmpty {
                    emptyBlock
                } else {
                    content()
                }
            }
        }
        .onChange(of: error) { _, newError in
            if let newError { AccessibilityNotification.Announcement(newError).post() }
        }
    }

    private func errorBlock(_ message: String, centered: Bool) -> some View {
        VStack(spacing: 10) {
            if let errorIcon {
                Image(systemName: errorIcon)
                    .font(.title2)
                    .foregroundStyle(Theme.danger)
                    .accessibilityHidden(true)
            }
            if let errorTitle {
                Text(errorTitle).font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.danger)
                .multilineTextAlignment(centered ? .center : .leading)
            if let retry {
                retryButton(retry, centered: centered)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .padding(.top, centered ? topPadding : 0)
    }

    @ViewBuilder
    private func retryButton(_ retry: @escaping () async -> Void, centered: Bool) -> some View {
        if centered {
            Button(retryTitle) { Task { await retry() } }
                .buttonStyle(OutlineButtonStyle())
                .disabled(isLoading)
        } else {
            Button { Task { await retry() } } label: { tapTarget(retryTitle) }
                .disabled(isLoading)
        }
    }

    private var emptyBlock: some View {
        VStack(spacing: 10) {
            if let emptyIcon {
                Image(systemName: emptyIcon)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            if let emptyTitle {
                Text(emptyTitle).font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(emptyText)
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
            if let emptyActionTitle, let emptyAction {
                Button(action: emptyAction) { tapTarget(emptyActionTitle) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, topPadding)
    }

    /// Padding and hit shape live inside the label so the whole area is tappable.
    private func tapTarget(_ title: String) -> some View {
        Text(title)
            .padding(.horizontal, 12)
            .frame(minHeight: Theme.minTapSize)
            .contentShape(Rectangle())
    }
}
