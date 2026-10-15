import SwiftUI

@main
struct CLOVApp: App {
    @StateObject private var appState = AppState()
    @UIApplicationDelegateAdaptor(CLOVAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(Theme.accent)
                .preferredColorScheme(.light)
                .onOpenURL { url in handle(url) }
                .task(id: appState.session?.user.id) {
                    if appState.isSignedIn {
                        appDelegate.requestPushPermission()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .clovAPNsToken)) { notification in
                    guard let token = notification.object as? String, appState.isSignedIn else { return }
                    Task { try? await API.registerDeviceToken(token, userId: appState.userId) }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await appState.restoreSessionIfNeeded() }
                }
        }
    }

    /// Parses `clov://vote/<uuid>` from a shared link (see
    /// ShareLinkButton) into `appState.deepLinkFitCheckId`, which
    /// MainTabView presents. Not in the original CLAUDE.md scope;
    /// added on request.
    private func handle(_ url: URL) {
        guard url.scheme == "clov", url.host == "vote",
              let id = UUID(uuidString: url.lastPathComponent)
        else { return }
        appState.deepLinkFitCheckId = id
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    #if DEBUG
    @State private var didRunDebugHooks = false
    #endif

    var body: some View {
        Group {
            if appState.isBootstrapping || (appState.isSignedIn && appState.isLoadingProfile) {
                ProgressView()
            } else if !appState.isSignedIn {
                AuthView()
            } else if let error = appState.profileLoadError {
                VStack(spacing: 16) {
                    Text(error)
                        .multilineTextAlignment(.center)
                    #if DEBUG
                    if let detail = appState.profileLoadDebugError {
                        Text(detail)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                    #endif
                    Button("Try again") {
                        Task { await appState.refreshProfile() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Log out") {
                        Task { await appState.signOut() }
                    }
                }
                .padding(24)
            } else if appState.isOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        #if DEBUG
        .task {
            // AppState's auth listener (started in its own init) is
            // already running by the time this fires — safe to layer
            // debug-only setup on top without racing it.
            await appState.autoLoginForUITestsIfRequested()
        }
        .onChange(of: appState.isBootstrapping) { _, bootstrapping in
            guard !bootstrapping, !didRunDebugHooks else { return }
            didRunDebugHooks = true
            DebugVerify.runIfRequested()
        }
        #endif
    }
}
