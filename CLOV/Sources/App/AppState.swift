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
        defer {
            if session?.user.id == id { isLoadingProfile = false }
        }
        do {
            let fetched = try await API.fetchProfile(id: id)
            guard session?.user.id == id else { return }
            profile = fetched
        } catch {
            guard session?.user.id == id else { return }
            profileLoadError = "We couldn’t load your profile. Please try again."
            print("refreshProfile failed: \(error)")
        }
    }

    func signOut() async {
        try? await SupabaseManager.client.auth.signOut()
        // The signOut event arrives via listenForAuthChanges() and
        // clears session/profile there.
    }
}
