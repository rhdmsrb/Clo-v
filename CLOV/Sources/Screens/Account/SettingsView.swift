import SwiftUI
import UserNotifications

/// Everything about the account and the app in one place: who you are,
/// how the app looks, notifications, privacy, and signing out.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppearanceKey.paletteID) private var paletteID = ThemePalette.rose.id
    @AppStorage(AppearanceKey.colorScheme) private var colorSchemeRaw = AppearanceMode.system.rawValue

    @State private var pushPermission = PushPermission.unknown
    @State private var showingEditProfile = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var error: String?

    private static let policyURL = URL(string: "https://github.com/rhdmsrb/Clo-v/blob/main/PRIVACY.md")!

    private var appearanceSummary: String {
        let mode = AppearanceMode(rawValue: colorSchemeRaw) ?? .system
        return "\(ThemePalette.resolve(paletteID).name) · \(mode.title)"
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                accountCard
                SettingsSection(title: "Account") { accountRows }
                SettingsSection(title: "Preferences") { preferenceRows }
                SettingsSection(title: "Privacy & safety") { privacyRows }
                SettingsSection(title: "About") { aboutRows }
                SettingsSection(title: "Session") { sessionRows }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
            .padding(20)
            // Leave room for the floating tab bar.
            .padding(.bottom, 88)
        }
        .background(Theme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshPushPermission() }
        // Returning from the system permission prompt or iOS Settings.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshPushPermission() } }
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(profile: appState.profile)
        }
        .alert("Delete your account?", isPresented: $showingDeleteConfirmation) {
            Button("Delete account", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your profile, Fit-Checks, photos, votes, comments, friends, and wardrobe items. This can't be undone.")
        }
    }

    // MARK: - Sections

    private var accountCard: some View {
        HStack(spacing: 14) {
            AvatarView(url: appState.profile?.avatarUrl, nickname: appState.profile?.nickname, size: 64, ringed: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.profile?.nickname ?? "Your profile")
                    .font(Theme.title)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let email = appState.email {
                    Text(email)
                        .font(Theme.font(.footnote))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let joined = appState.profile?.createdAt {
                    Text("Member since \(joined.formatted(.dateTime.month(.wide).year()))")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(radius: Theme.cardRadius)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var accountRows: some View {
        Button { showingEditProfile = true } label: {
            SettingsRowLabel(icon: "person.crop.circle", title: "Edit profile", detail: styleSummary)
        }
        .buttonStyle(InstantPressStyle())
        .accessibilityIdentifier("settingsEditProfile")
    }

    @ViewBuilder
    private var preferenceRows: some View {
        NavigationLink(destination: AppearanceView()) {
            SettingsRowLabel(icon: "paintpalette", title: "Appearance", detail: appearanceSummary, tint: Theme.iconPlum)
        }
        .buttonStyle(InstantPressStyle())
        .accessibilityIdentifier("settingsAppearance")
        SettingsDivider()
        notificationsRow
    }

    @ViewBuilder
    private var notificationsRow: some View {
        switch pushPermission {
        case .notDetermined:
            Button { requestPushPermission() } label: {
                SettingsRowLabel(icon: "bell.badge", title: "Notifications", detail: pushPermission.summary, tint: Theme.iconApricot)
            }
            .buttonStyle(InstantPressStyle())
            .accessibilityHint("Asks for permission to send notifications")
        case .denied:
            Button(action: openSystemSettings) {
                SettingsRowLabel(icon: "bell.slash", title: "Notifications", detail: pushPermission.summary, tint: Theme.iconApricot, isExternal: true)
            }
            .buttonStyle(InstantPressStyle())
            .accessibilityHint("Opens iOS Settings")
        case .allowed, .unknown:
            Button(action: openSystemSettings) {
                SettingsRowLabel(icon: "bell", title: "Notifications", detail: pushPermission.summary, tint: Theme.iconApricot, isExternal: true)
            }
            .buttonStyle(InstantPressStyle())
            .accessibilityHint("Opens iOS Settings to change what you receive")
        }
    }

    @ViewBuilder
    private var privacyRows: some View {
        NavigationLink(destination: PrivacyView()) {
            SettingsRowLabel(icon: "lock.shield", title: "Privacy & data", detail: "What CLO·V stores and why", tint: Theme.iconSage)
        }
        .buttonStyle(InstantPressStyle())
        .accessibilityIdentifier("settingsPrivacy")
        SettingsDivider()
        Button { openURL(Self.policyURL) } label: {
            SettingsRowLabel(icon: "doc.text", title: "Privacy policy", detail: "Opens in your browser", tint: Theme.iconSage, isExternal: true)
        }
        .buttonStyle(InstantPressStyle())
    }

    @ViewBuilder
    private var aboutRows: some View {
        SettingsRowLabel(icon: "info.circle", title: "Version", detail: versionText, tint: Theme.iconPlum, showsChevron: false)
    }

    @ViewBuilder
    private var sessionRows: some View {
        Button { Task { await appState.signOut() } } label: {
            SettingsRowLabel(icon: "rectangle.portrait.and.arrow.right", title: "Log out", tint: Theme.iconCoral, showsChevron: false)
        }
        .buttonStyle(InstantPressStyle())
        .accessibilityIdentifier("settingsLogOut")
        SettingsDivider()
        Button(role: .destructive) { showingDeleteConfirmation = true } label: {
            SettingsRowLabel(
                icon: "trash",
                title: isDeletingAccount ? "Deleting account…" : "Delete account",
                detail: "Permanently removes your profile and content",
                tint: Theme.danger,
                titleColor: Theme.danger,
                showsChevron: false
            )
        }
        .buttonStyle(InstantPressStyle())
        .disabled(isDeletingAccount)
        .accessibilityIdentifier("settingsDeleteAccount")
    }

    // MARK: - Actions

    private var styleSummary: String? {
        guard let styles = appState.profile?.stylePreferences, !styles.isEmpty else { return "Nickname and style" }
        return styles.joined(separator: ", ")
    }

    private func refreshPushPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        pushPermission = PushPermission(settings.authorizationStatus)
    }

    private func requestPushPermission() {
        Task {
            let granted = await Log.attempt("Push permission request") {
                try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            } ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            await refreshPushPermission()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        error = nil
        defer { isDeletingAccount = false }
        do {
            try await API.deleteAccount()
            appState.accountDeleted()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
