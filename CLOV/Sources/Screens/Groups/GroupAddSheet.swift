import SwiftUI

/// Group Add (spec 5.6b): join with a code, or create a group and invite via share sheet.
struct GroupAddSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case join = "Join"
        case create = "Create"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let initialMode: Mode
    let onChanged: () async -> Void

    @State private var mode: Mode
    @State private var joinCode = ""
    @State private var name = ""
    @State private var error: String?
    @State private var isWorking = false
    @State private var createdGroup: FashionGroup?
    @State private var joinedGroup: FashionGroup?

    init(initialMode: Mode = .join, onChanged: @escaping () async -> Void) {
        self.initialMode = initialMode
        self.onChanged = onChanged
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a group")
                .font(Theme.displayFont)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityAddTraits(.isHeader)
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("groupAdd.mode")
            .onChange(of: mode) { _, _ in error = nil }

            if let createdGroup {
                createdContent(createdGroup)
            } else if let joinedGroup {
                joinedContent(joinedGroup)
            } else if mode == .join {
                joinContent
            } else {
                createContent
            }
            if let error {
                Text(error).font(Theme.caption).foregroundStyle(Theme.danger)
            }
            Spacer()
        }
        .padding(24)
        .presentationCornerRadius(32)
        .presentationBackground(Theme.cardElevated)
        .accessibilityIdentifier("groupAdd.root")
    }

    private var joinContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter the code a friend shared with you.")
                .font(Theme.body)
                .foregroundStyle(Theme.mutedForeground)
            TextField("ABC234", text: $joinCode)
                .font(Theme.body)
                .accessibilityLabel("Invite code")
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .frame(minHeight: Theme.minTapSize)
                .background(Theme.muted, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
            if InviteCodeInput.hasAmbiguousCharacters(joinCode) {
                Text(InviteCodeInput.hint)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityIdentifier("groupAdd.codeHint")
            }
            Button(isWorking ? "Joining…" : "Join with invite code") { Task { await join() } }
                .buttonStyle(PrimaryButtonStyle(isDisabled: isWorking))
                .disabled(isWorking)
        }
    }

    private var createContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name your group, then invite friends with a private code.")
                .font(Theme.body)
                .foregroundStyle(Theme.mutedForeground)
            TextField("Name your group", text: $name)
                .font(Theme.body)
                .padding(.horizontal, 16)
                .frame(minHeight: Theme.minTapSize)
                .background(Theme.muted, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
            Button(isWorking ? "Please wait…" : "Create group") { Task { await create() } }
                .buttonStyle(PrimaryButtonStyle(isDisabled: isWorking))
                .disabled(isWorking)
        }
    }

    private func createdContent(_ group: FashionGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(group.name) is ready")
                .font(Theme.headline)
                .foregroundStyle(Theme.ink)
            Text("Share this code so friends can join.")
                .font(Theme.body)
                .foregroundStyle(Theme.mutedForeground)
            InviteCodeCapsule(code: group.inviteCode)
            HStack(spacing: 8) {
                Text("Invite via")
                    .font(Theme.label)
                    .foregroundStyle(Theme.mutedForeground)
                ShareLink(item: GroupInvite.text(for: group)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(OutlineButtonStyle())
                .accessibilityIdentifier("groupAdd.share")
            }
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private func joinedContent(_ group: FashionGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You joined \(group.name)")
                .font(Theme.headline)
                .foregroundStyle(Theme.ink)
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private func join() async {
        error = nil
        isWorking = true
        defer { isWorking = false }
        do {
            joinedGroup = try await API.joinGroup(code: InviteCodeInput.normalize(joinCode))
            Haptics.success()
            joinCode = ""
            await onChanged()
        } catch {
            Haptics.error()
            self.error = friendlyMessage(for: error, fallback: "Couldn’t join that group. Please try again.")
        }
    }

    private func create() async {
        let trimmedName: String
        do { trimmedName = try GroupNameValidator.validated(name) } catch {
            self.error = friendlyMessage(for: error, fallback: GroupNameValidator.message)
            return
        }
        error = nil
        isWorking = true
        defer { isWorking = false }
        do {
            createdGroup = try await API.createGroup(name: trimmedName, creatorId: appState.userId)
            Haptics.success()
            await onChanged()
        } catch {
            Haptics.error()
            self.error = friendlyMessage(for: error, fallback: "Couldn’t create the group. Please try again.")
        }
    }
}

/// Invite text shared via the system share sheet. A link is not used until
/// `CLOVShareBaseURL` is configured (spec D12), so the code is shared as text.
enum GroupInvite {
    static func text(for group: FashionGroup) -> String {
        "Join my group \(group.name) on CLO·V — invite code: \(group.inviteCode)"
    }
}
