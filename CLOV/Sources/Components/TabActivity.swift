import SwiftUI

private struct IsTabActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// `false` for tabs that are mounted but not currently visible.
    var isTabActive: Bool {
        get { self[IsTabActiveKey.self] }
        set { self[IsTabActiveKey.self] = newValue }
    }
}

/// Runs `action` when the view is on the visible tab and `revision` is newer
/// than the last revision it finished loading. Hidden tabs skip work and catch
/// up lazily when they become visible.
private struct RevisionTask<Key: Equatable>: ViewModifier {
    let revision: Key
    let action: () async -> Void
    @Environment(\.isTabActive) private var isTabActive
    @State private var loadedRevision: Key?

    func body(content: Content) -> some View {
        content.task(id: isTabActive ? revision : nil) {
            guard isTabActive, loadedRevision != revision else { return }
            await action()
            if !Task.isCancelled { loadedRevision = revision }
        }
    }
}

extension View {
    func revisionTask<Key: Equatable>(_ revision: Key, perform action: @escaping () async -> Void) -> some View {
        modifier(RevisionTask(revision: revision, action: action))
    }
}
