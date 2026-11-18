import SwiftUI
import Supabase
import AuthenticationServices
import CryptoKit

struct AuthView: View {
    @EnvironmentObject private var appState: AppState

    private enum Mode {
        case welcome, signIn, signUp

        var title: String { self == .signUp ? "Sign up" : "Log in" }
        var heading: String { self == .signUp ? "Create your account" : "Welcome back!" }
        var subtitle: String {
            self == .signUp
                ? "Join CLO·V and share your looks with your circle."
                : "Log in to see what your circle is wearing."
        }
        var switchPrompt: String { self == .signUp ? "Already have an account?" : "Don’t have an account?" }
        var switchAction: String { self == .signUp ? "Log in" : "Sign up" }
    }

    private enum Field: Hashable {
        case email
        case password
    }

    @State private var mode: Mode = .welcome
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var error: String?
    @State private var isSubmitting = false
    @State private var checkEmailNotice = false
    @State private var showingPasswordReset = false
    @State private var resetEmail = ""
    @State private var resetNotice: String?
    @FocusState private var focusedField: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Share of the screen the photo keeps above the form sheet.
    private static let heroFraction: CGFloat = 0.36
    private static let sheetRadius: CGFloat = 28
    private static let maxFormWidth: CGFloat = 520

    private var canSubmit: Bool {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.contains("@") && password.count >= 6
    }

    var body: some View {
        Group {
            if mode == .welcome { welcome } else { form }
        }
        .animation(Theme.animation(Theme.settle, reduceMotion: reduceMotion), value: mode)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .sheet(isPresented: $showingPasswordReset) { resetSheet }
    }

    // MARK: - Welcome

    /// Full-bleed cover photo with the wordmark and two choices at the foot.
    private var welcome: some View {
        AuthHeroPhoto()
            .ignoresSafeArea()
            .overlay {
                LinearGradient(colors: [.black.opacity(0.25), .clear, .clear, .black.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                AuthWordmark(tagline: "Your look, your circle")
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.m)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: Spacing.sm) {
                    Button("Log in") { open(.signIn) }
                        .buttonStyle(AuthCoverButtonStyle())
                        .accessibilityIdentifier("auth.welcome.login")
                    Button("Sign up") { open(.signUp) }
                        .buttonStyle(AuthCoverButtonStyle(isFrosted: true))
                        .accessibilityIdentifier("auth.welcome.signup")
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.l)
                .frame(maxWidth: Self.maxFormWidth)
            }
            .transition(.opacity)
    }

    // MARK: - Log in / Sign up

    /// Photo on top, a white rounded sheet with the form below.
    private var form: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    formHero(height: proxy.size.height * Self.heroFraction + proxy.safeAreaInsets.top)
                    formSheet
                        .padding(.top, -Self.sheetRadius)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(edges: .top)
        }
        .background(Theme.card.ignoresSafeArea())
        .transition(.opacity)
    }

    private func formHero(height: CGFloat) -> some View {
        AuthHeroPhoto(alignment: .top)
            .frame(height: height)
            .overlay {
                LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .top, endPoint: .center)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Button { open(.welcome) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                            .background(.black.opacity(0.25), in: Circle())
                    }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("auth.back")
                    AuthWordmark(tagline: "Your look, your circle")
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.xxl + Spacing.m)
            }
    }

    private var formSheet: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(mode.heading)
                    .font(Theme.font(.title2, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(mode.subtitle)
                    .font(Theme.font(.subheadline))
                    .foregroundStyle(Theme.mutedForeground)
            }
            if checkEmailNotice { checkEmailBanner }
            fields
            if mode == .signIn { passwordResetButton }
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
            }
            submitButton
            orDivider
            SocialSignInButtons(error: $error, isBusy: $isSubmitting)
            secondaryActions
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.l + Spacing.xs)
        .padding(.bottom, Spacing.xl)
        .frame(maxWidth: Self.maxFormWidth)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Self.sheetRadius, topTrailingRadius: Self.sheetRadius,
                                   style: .continuous)
                .fill(Theme.card)
        }
    }

    private func open(_ target: Mode) {
        mode = target
        error = nil
        if target == .welcome { checkEmailNotice = false }
        focusedField = nil
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.controlBorder).frame(height: 1)
            Text("or")
                .font(Theme.caption)
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize()
            Rectangle().fill(Theme.controlBorder).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var checkEmailBanner: some View {
        Label("Check your email to confirm your account, then log in.", systemImage: "envelope.badge")
            .font(Theme.bodyEmphasis)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            AuthInputRow(systemImage: "envelope", isFocused: focusedField == .email) {
                TextField("Email address", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .accessibilityLabel("Email")
                    .accessibilityIdentifier("auth.email")
            }
            AuthInputRow(
                systemImage: "lock",
                isFocused: focusedField == .password,
                errorMessage: !password.isEmpty && password.count < 6 ? "Use at least 6 characters." : nil
            ) {
                passwordField
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit {
                        guard canSubmit else { return }
                        Task { await submit() }
                    }
                    .accessibilityLabel("Password")
                    .accessibilityIdentifier("auth.password")
            } trailing: {
                Button { isPasswordVisible.toggle() } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
            }
        }
    }

    @ViewBuilder
    private var passwordField: some View {
        if isPasswordVisible {
            TextField("Password", text: $password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            SecureField("Password", text: $password)
        }
    }

    private var submitButton: some View {
        Button {
            focusedField = nil
            Task { await submit() }
        } label: {
            if isSubmitting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Please wait…")
                }
            } else {
                Text(mode.title)
            }
        }
        .buttonStyle(PrimaryButtonStyle(isDisabled: isSubmitting || !canSubmit))
        .disabled(isSubmitting || !canSubmit)
        .accessibilityIdentifier("auth.submit")
    }

    private var secondaryActions: some View {
        Button {
            open(mode == .signIn ? .signUp : .signIn)
        } label: {
            (Text(mode.switchPrompt + " ").foregroundStyle(Theme.mutedForeground)
                + Text(mode.switchAction).foregroundStyle(Theme.accentDeep).bold())
                .font(Theme.font(.subheadline))
                .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("auth.switchMode")
    }

    private var passwordResetButton: some View {
        Button {
            resetEmail = email.trimmingCharacters(in: .whitespaces)
            resetNotice = nil
            showingPasswordReset = true
        } label: {
            // The whole row is the target, not just the words at its trailing edge.
            Text("Forgot password?")
                .font(Theme.font(.footnote, weight: .semibold))
                .foregroundStyle(Theme.accentDeep)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapSize, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, -Spacing.s)
        .accessibilityIdentifier("auth.forgotPassword")
    }

    private var resetEmailIsEmpty: Bool {
        resetEmail.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var resetSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reset your password")
                    .font(Theme.font(.title2, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityAddTraits(.isHeader)
                Text("We'll send a secure password reset link to your email.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.mutedForeground)
                AuthInputRow(systemImage: "envelope") {
                    TextField("Email address", text: $resetEmail)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let resetNotice {
                    let failed = resetNotice.hasPrefix("We couldn't")
                    Label(resetNotice, systemImage: failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(Theme.caption)
                        .foregroundStyle(failed ? Theme.danger : Theme.mutedForeground)
                }
                Button("Send reset link") { Task { await sendPasswordReset() } }
                    .buttonStyle(PrimaryButtonStyle(isDisabled: resetEmailIsEmpty))
                    .disabled(resetEmailIsEmpty)
                Spacer()
            }
            .padding(24)
            .background(Theme.card)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(Theme.cardRadius)
    }

    private func submit() async {
        error = nil
        checkEmailNotice = false

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        #if DEBUG
        // Keep the old synthetic credentials testable in Debug builds without
        // shipping a special-case login path in the production binary.
        if trimmedEmail == "1", password == "1" {
            error = "Use your real account to log in. The old 1 / 1 shortcut cannot save your profile."
            return
        }
        #endif


        guard !trimmedEmail.isEmpty, password.count >= 6 else {
            error = "Enter a valid email and a password of at least 6 characters."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            switch mode {
            case .signIn:
                // A successful call updates the session internally;
                // AppState's auth-state listener picks it up and routes
                // on automatically — nothing to do here but wait.
                try await SupabaseManager.client.auth.signIn(email: trimmedEmail, password: password)
            case .signUp:
                let response = try await SupabaseManager.client.auth.signUp(email: trimmedEmail, password: password)
                if case .user = response {
                    // No session yet — email confirmation is required.
                    checkEmailNotice = true
                    mode = .signIn
                }
            case .welcome:
                return // The welcome cover has no form to submit.
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendPasswordReset() async {
        let address = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        do {
            try await SupabaseManager.client.auth.resetPasswordForEmail(address, redirectTo: AppConfig.authCallbackURL)
            AuthCallbackGate.shared.markResetRequested()
            resetNotice = "Check your email for a password reset link."
        } catch {
            resetNotice = "We couldn't send the reset link. Please check the email and try again."
        }
    }
}

/// Full-bleed hero used by Auth, Onboarding intro and New Password: gradient
/// surface, Bodoni title, short value copy. White on every gradient stop is >= 4.5:1.
struct AuthHeroBlock: View {
    let title: String
    let subtitle: String
    /// Space above the wordmark. Auth passes a smaller value so the whole
    /// login form fits above the home indicator on current iPhones.
    var topInset: CGFloat = 72

    private static let bottomRadius: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").accessibilityHidden(true)
                Text("CLO·V")
                    .font(Theme.editorialFont(size: 28, relativeTo: .title2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.white)
            Spacer(minLength: 12)
            Text(title)
                .font(Theme.editorialFont(size: 44, relativeTo: .largeTitle))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(Theme.body)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, topInset)
        .padding(.bottom, 32)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: Self.bottomRadius, bottomTrailingRadius: Self.bottomRadius, style: .continuous)
                .fill(Theme.heroGradient)
        }
    }
}


/// "Continue with Apple" (native, ID token -> Supabase) and "Continue with
/// Google" (Supabase OAuth in a web auth session). Both end in the same
/// session update the email flow uses, so AppState's auth listener routes on.
/// Apple and Google must also be enabled under Supabase > Authentication >
/// Providers, and `clov://auth-callback` listed as a Redirect URL.
struct SocialSignInButtons: View {
    @Binding var error: String?
    @Binding var isBusy: Bool
    @State private var rawNonce = ""
    /// Scales with the "Continue with Google" label beside it.
    @ScaledMetric(relativeTo: .body) private var googleGlyphSize: CGFloat = 20

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Button { Task { await signInWithGoogle() } } label: {
                HStack(spacing: 10) {
                    Text("G").font(.system(size: googleGlyphSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                        .accessibilityHidden(true)
                    Text("Continue with Google").font(Theme.bodyEmphasis)
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
                .background(Theme.card, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(Theme.controlBorder, lineWidth: 1))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            SignInWithAppleButton(.continue) { request in
                rawNonce = Self.randomNonce()
                request.requestedScopes = [.fullName, .email]
                request.nonce = Self.sha256(rawNonce)
            } onCompletion: { result in
                Task { await handleApple(result) }
            }
            // Borderless style, clipped to a pill, with our own outline so it matches Google's.
            .signInWithAppleButtonStyle(.white)
            .frame(height: Self.buttonHeight)
            .clipShape(Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Theme.controlBorder, lineWidth: 1).allowsHitTesting(false))
            .disabled(isBusy)
        }
    }

    private static let buttonHeight: CGFloat = 50

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code == .canceled { return }
            error = failure.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                error = "Apple sign-in didn't return a token. Please try again."
                return
            }
            error = nil
            isBusy = true
            defer { isBusy = false }
            do {
                try await SupabaseManager.client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce)
                )
            } catch let failure {
                error = failure.localizedDescription
            }
        }
    }

    private func signInWithGoogle() async {
        error = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await SupabaseManager.client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: AppConfig.authCallbackURL
            )
        } catch let failure {
            if (failure as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            error = failure.localizedDescription
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        precondition(SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
