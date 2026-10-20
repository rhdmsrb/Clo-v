import SwiftUI

/// Plain-language explanation of the data CLO-V stores and why it is needed.
/// Keep this screen aligned with the public PRIVACY.md policy before release.
struct PrivacyView: View {
    private let policyURL = URL(string: "https://github.com/rhdmsrb/Clo-v/blob/main/PRIVACY.md")!

    var body: some View {
        List {
            Section {
                Text("CLO-V uses your information to let you create Fit-Checks, vote on outfits, manage your wardrobe, and connect with friends.")
                    .font(.body)
                    .foregroundStyle(Theme.mutedForeground)
            }

            Section("What we store") {
                privacyRow("Account", "Email address and a user ID so you can sign in and keep your account secure.")
                privacyRow("Profile", "Nickname, avatar, and style preferences that you choose to show to other users.")
                privacyRow("Photos", "Fit-Check and wardrobe photos that you upload. Photos are stored privately and shown through temporary secure links.")
                privacyRow("Virtual try-on", "Optional. When you tap Try on, the full-body photo you pick and your selected wardrobe photos are sent to WEARFITS to make a preview image. We don't save the full-body photo.")
                privacyRow("Activity", "Votes, short comments, friendships, and wardrobe categories needed for the app to work.")
            }

            Section("Your choices") {
                Text("You can update your profile, delete your Fit-Checks, remove wardrobe items, or permanently delete your account from the Account screen. Account deletion removes your profile and the content associated with it.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)
            }

            Section {
                Link(destination: policyURL) {
                    Label("Read the full privacy policy", systemImage: "arrow.up.right.square")
                }
            }
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacyRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(Theme.mutedForeground)
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    NavigationStack { PrivacyView() }
}
