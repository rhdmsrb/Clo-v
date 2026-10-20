import SwiftUI

@main
struct CLOVApp: App {
    @StateObject private var appState = AppState()
    @UIApplicationDelegateAdaptor(CLOVAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasAskedForPush = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(Theme.accent)
                .preferredColorScheme(.light)
                .onOpenURL { url in handle(url) }
                .task(id: appState.session?.user.id) {
                    // No prompt on sign-in: only refresh the token if the user
                    // already allowed notifications.
                    if appState.isSignedIn {
                        appDelegate.registerIfAuthorized()
                    }
                }
                .onChange(of: appState.contentRevision) { _, _ in
                    // First vote, comment or post: now notifications have a reason to exist.
                    guard appState.isSignedIn, !hasAskedForPush else { return }
                    hasAskedForPush = true
                    appDelegate.requestPushPermission()
                }
                .onReceive(NotificationCenter.default.publisher(for: .clovAPNsToken)) { notification in
                    guard let token = notification.object as? String, appState.isSignedIn else { return }
                    Task {
                        do { try await API.registerDeviceToken(token) }
                        catch { Log.push.error("Device token registration failed: \(error.localizedDescription)") }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .clovOpenFitCheck)) { notification in
                    openPushedFitCheck(notification.object as? UUID)
                }
                .onChange(of: appState.isSignedIn) { _, signedIn in
                    // A push tapped on cold launch is held until the user is signed in.
                    if signedIn { openPushedFitCheck(appDelegate.takePendingFitCheckId()) }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await appState.restoreSessionIfNeeded() }
                }
        }
    }

    /// Presents a Fit-Check from a tapped push. While signed out the id stays
    /// pending in the app delegate and opens after sign-in.
    private func openPushedFitCheck(_ id: UUID?) {
        guard let id, appState.isSignedIn else { return }
        _ = appDelegate.takePendingFitCheckId()
        appState.deepLinkFitCheckId = id
    }

    /// Parses `clov://vote/<uuid>` from a shared link (see
    /// ShareLinkButton) into `appState.deepLinkFitCheckId`, which
    /// MainTabView presents. Not in the original CLAUDE.md scope;
    /// added on request.
    private func handle(_ url: URL) {
        if url.scheme == "clov", url.host == "auth-callback" {
            // Password-reset link: exchanging it signs the user in and makes
            // the auth client emit `.passwordRecovery`, which AppState turns
            // into the new-password screen.
            Task {
                do { _ = try await SupabaseManager.client.auth.session(from: url) }
                catch { Log.app.error("Auth callback failed: \(error.localizedDescription)") }
            }
            return
        }
        guard let id = ShareURL.fitCheckId(from: url) else { return }
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
            } else if appState.isRecoveringPassword && appState.isSignedIn {
                NewPasswordView()
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
