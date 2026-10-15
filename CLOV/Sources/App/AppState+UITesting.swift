import Foundation

#if DEBUG
extension AppState {
    /// Signs in (creating the account on first run) as a fixed test user
    /// when launched with `--uiTestAutoLogin` + `UITEST_EMAIL`/
    /// `UITEST_PASSWORD` env vars, and auto-completes onboarding if
    /// needed — lets XCUITests reach the signed-in app without scripting
    /// the AuthView form on every run. No-ops otherwise.
    func autoLoginForUITestsIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard ProcessInfo.processInfo.arguments.contains("--uiTestAutoLogin"),
              let email = env["UITEST_EMAIL"], let password = env["UITEST_PASSWORD"]
        else { return }

        do {
            try await SupabaseManager.client.auth.signIn(email: email, password: password)
        } catch {
            // Doesn't exist yet on a fresh backend — create it. If
            // email confirmation is required this leaves session nil,
            // same as a real user would see.
            _ = try? await SupabaseManager.client.auth.signUp(email: email, password: password)
        }

        // The signIn/signUp call above updates the session, but
        // AppState's listener picks it up asynchronously — give it a
        // moment before checking.
        for _ in 0..<20 where session == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let uid = session?.user.id else { return }

        await refreshProfile()
        if profile?.isOnboarded != true {
            try? await API.saveOnboarding(nickname: "uitester", styles: ["Streetwear"])
            await refreshProfile()
            // Some test backends require email confirmation before profile
            // writes even though an existing auth session can launch the app.
            // Keep screenshot/UI tests deterministic without changing the
            // production onboarding path or persisting a fake profile.
            if profile?.isOnboarded != true {
                profile = Profile(
                    id: uid,
                    nickname: "uitester",
                    stylePreferences: ["Streetwear"],
                    avatarUrl: nil,
                    createdAt: nil
                )
                // The fallback profile is intentional for local UI testing
                // when the test backend requires confirmed email/RLS access.
                // Do not leave RootView blocked by the transient fetch error.
                clearProfileLoadErrorForUITesting()
            }
        }
    }
}
#endif
