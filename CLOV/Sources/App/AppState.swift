import Foundation
import Supabase

@MainActor
final class AppState: ObservableObject {
    /// Invalidates visible lists after successful content mutations.
    @Published private(set) var contentRevision = 0

    func contentDidChange() { contentRevision += 1 }

    @Published var session: Session?
    @Published var profile: Profile?
    @Published var isBootstrapping = true
    @Published private(set) var isLoadingProfile = false
    @Published private(set) var profileLoadError: String?
    #if DEBUG
    @Published private(set) var profileLoadDebugError: String?
    #endif
    private var lastSessionCheck: Date?

    /// Set from a `clov://vote/<id>` link (see .onOpenURL in CLOVApp) —
    /// MainTabView presents FitCheckDetailView for it. Not in the
    /// original CLAUDE.md scope; added on request alongside the
    /// per-post share link.
    @Published var deepLinkFitCheckId: UUID?

    // Only a real Supabase session can authorize backend writes.
    var isSignedIn: Bool { session != nil }

    var isOnboarded: Bool { profile?.isOnboarded ?? false }

    var email: String? { session?.user.email }

    /// Only valid once `isSignedIn` is true. Every screen that reads
    /// this is behind RootView's sign-in gate (AuthView shows instead
    /// otherwise), so hitting the fatalError here means something
    /// routed to a screen it shouldn't have.
    var userId: UUID {
        if let id = session?.user.id { return id }
        fatalError("AppState.userId read while signed out")
    }

    init() {
        Task { await listenForAuthChanges() }
    }

    /// Runs for the app's lifetime — Supabase always emits an
    /// `.initialSession` event first, which is what resolves
    /// `isBootstrapping` on a cold launch; every sign-in/out/token
    /// refresh after that flows through the same place.
    private func listenForAuthChanges() async {
        for await (_, session) in SupabaseManager.client.auth.authStateChanges {
            // Set the loading flag before publishing the authenticated session.
            // RootView must not interpret a temporarily nil profile as incomplete
            // onboarding while this request is in flight.
            isLoadingProfile = session != nil
            profileLoadError = nil
            self.session = session
            if session != nil {
                await refreshProfile()
            } else {
                profile = nil
            }
            isBootstrapping = false
        }
    }

    func refreshProfile() async {
        guard let id = session?.user.id else { return }
        isLoadingProfile = true
        profileLoadError = nil
        #if DEBUG
        profileLoadDebugError = nil
        #endif
        defer {
            if session?.user.id == id { isLoadingProfile = false }
        }
        do {
            let fetched = try await API.fetchProfile(id: id)
            guard session?.user.id == id else { return }
            profile = fetched
        } catch {
            guard session?.user.id == id else { return }
            if let authError = error as? AuthError, authError == .sessionMissing {
                // Preserve the auth event's session so the underlying SDK
                // failure remains visible and retryable. Signing out here
                // hides whether this is a session persistence race or an
                // invalid session returned by the auth service.
            }
            profileLoadError = "We couldn’t load your profile. Please try again."
            #if DEBUG
            profileLoadDebugError = String(describing: error)
            #endif
            Log.app.error("refreshProfile failed: \(error.localizedDescription)")
        }
    }

    #if DEBUG
    func clearProfileLoadErrorForUITesting() { profileLoadError = nil }
    #endif

    /// Revalidates the persisted session when the app returns to the
    /// foreground. Read `auth.session` so Supabase's session manager owns
    /// refresh coordination; manually rotating refresh tokens here can race
    /// the SDK's own auto-refresh and invalidate a just-issued token.
    func restoreSessionIfNeeded() async {
        guard let current = session else { return }
        if let lastSessionCheck, Date().timeIntervalSince(lastSessionCheck) < 60 {
            return
        }
        lastSessionCheck = Date()
        do {
            let validSession = try await SupabaseManager.client.auth.session
            guard session?.refreshToken == current.refreshToken else { return }
            guard validSession.user.id == current.user.id else {
                await signOut()
                return
            }
            session = validSession
            await refreshProfile()
        } catch {
            // A stale foreground check must not clear a newer sign-in for
            // the same account after the user logs in while refresh is pending.
            guard session?.refreshToken == current.refreshToken else { return }
            await signOut()
        }
    }

    func signOut() async {
        // Clear the app state even if the auth service is unavailable. In
        // particular, an expired refresh token must not strand the user on
        // the profile error screen with no way back to the login form.
        session = nil
        profile = nil
        isLoadingProfile = false
        profileLoadError = nil
        #if DEBUG
        profileLoadDebugError = nil
        #endif
        lastSessionCheck = nil
        try? await SupabaseManager.client.auth.signOut(scope: .local)
    }

    /// Immediately returns the UI to the signed-out state after the server
    /// has permanently deleted the account.
    func accountDeleted() {
        session = nil
        profile = nil
        isLoadingProfile = false
        profileLoadError = nil
        lastSessionCheck = nil
        isBootstrapping = false
    }
}
