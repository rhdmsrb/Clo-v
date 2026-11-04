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

    @ViewBuilder
    private func errorBlock(_ message: String, centered: Bool) -> some View {
        if centered {
            EmptyStateView(
                icon: errorIcon ?? "exclamationmark.triangle",
                title: errorTitle ?? "Something went wrong",
                message: message,
                actionTitle: retry == nil ? nil : retryTitle,
                isActionDisabled: isLoading,
                tint: Theme.danger,
                action: retry.map { retry in { Task { await retry() } } }
            )
            .padding(.top, topPadding)
        } else {
            inlineError(message)
        }
    }

    private func inlineError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorTitle {
                Text(errorTitle).font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(message)
                .font(Theme.font(.footnote))
                .foregroundStyle(Theme.danger)
            if let retry {
                Button { Task { await retry() } } label: { tapTarget(retryTitle) }
                    .disabled(isLoading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyBlock: some View {
        EmptyStateView(
            icon: emptyIcon ?? "sparkles",
            title: emptyTitle ?? emptyText,
            message: emptyTitle == nil ? nil : emptyText,
            actionTitle: emptyActionTitle,
            action: emptyAction
        )
        .padding(.vertical, topPadding)
    }

    /// Padding and hit shape live inside the label so the whole area is tappable.
    private func tapTarget(_ title: String) -> some View {
        Text(title)
            .font(Theme.label)
            .foregroundStyle(Theme.accentDeep)
            .padding(.horizontal, 12)
            .frame(minHeight: Theme.minTapSize)
            .contentShape(Rectangle())
    }
}
