import SwiftUI
import PhotosUI

struct CreateFitCheckView: View {
    var preselectedGroup: FashionGroup? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var slots: [PhotoSlotState] = [.init(), .init()]
    @State private var photoCount = 2
    @State private var caption = ""
    @State private var myGroups: [FashionGroup] = []
    @State private var selectedGroupId: UUID?
    @State private var votingDuration: VotingDuration = .oneDay
    @State private var error: String?
    @State private var isPosting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Post a Fit-Check")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .accessibilityIdentifier("createFitCheckTitle")
                    Text("Upload 2 or 4 photos. Your circle votes for the best one.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)

                    HStack(spacing: 8) {
                        Text("PHOTOS").font(.system(.caption2).weight(.bold)).foregroundStyle(.secondary)
                        Spacer()
                        ForEach([2, 4], id: \.self) { count in
                            Button("\(count) photos") { photoCount = count }
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(photoCount == count ? .white : Theme.mutedForeground)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(photoCount == count ? Theme.accent : Theme.card)
                                .clipShape(Capsule())
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(slots.indices, id: \.self) { i in
                            PhotoSlotView(state: $slots[i], label: "Photo \(i + 1)")
                        }
                    }

                    LabeledField(label: "WHAT DO YOU NEED HELP WITH? (OPTIONAL)", padding: 8) {
                        TextEditor(text: $caption)
                            .frame(height: 80)
                            .overlay(alignment: .topLeading) {
                                if caption.isEmpty {
                                    Text("e.g. I'm going to dinner tonight — which outfit should I wear?")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.mutedForeground)
                                        .padding(.top, 8)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("VOTING WINDOW").font(.system(.caption2, design: .default).weight(.bold)).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(VotingDuration.allCases) { duration in
                                ChipToggle(label: duration.label, selected: votingDuration == duration) {
                                    votingDuration = duration
                                }
                            }
                        }
                        Text("Voting closes and results disappear after this — even for anyone who opens a shared link.")
                            .font(.caption2)
                            .foregroundStyle(Theme.mutedForeground)
                    }

                    if !myGroups.isEmpty {
                        LabeledField(label: "POST TO", padding: 12) {
                            Picker("Post to", selection: $selectedGroupId) {
                                Text("Public feed").tag(UUID?.none)
                                ForEach(myGroups) { group in
                                    Text(group.name).tag(Optional(group.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }

                    Button(isPosting ? "Posting…" : "Post it") { Task { await submit() } }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: isPosting))
                        .disabled(isPosting)
                }
                .padding(20)
            }
            .background(Theme.background)
            .onChange(of: photoCount) { _, newCount in
                if slots.count < newCount {
                    slots.append(contentsOf: Array(repeating: PhotoSlotState(), count: newCount - slots.count))
                } else if slots.count > newCount {
                    slots = Array(slots.prefix(newCount))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                myGroups = (try? await API.fetchMyGroups(profileId: appState.userId)) ?? []
                selectedGroupId = preselectedGroup?.id
            }
        }
    }

    private func submit() async {
        error = nil
        let images = slots.compactMap(\.image)
        guard images.count == photoCount else {
            error = "Upload exactly \(photoCount) photos."
            return
        }
        isPosting = true
        defer { isPosting = false }
        do {
            try await API.createFitCheck(
                creatorId: appState.userId,
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caption,
                groupId: selectedGroupId,
                votingDuration: votingDuration.seconds,
                photos: images
            )
            appState.contentDidChange()
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            self.error = error.localizedDescription
        }
    }
}

struct PhotoSlotState {
    var item: PhotosPickerItem?
    var image: UIImage?
}

/// Not in the original CLAUDE.md scope; added on request.
enum VotingDuration: CaseIterable, Identifiable {
    case oneHour, sixHours, oneDay

    var id: Self { self }
    var label: String {
        switch self {
        case .oneHour: "1 hour"
        case .sixHours: "6 hours"
        case .oneDay: "24 hours"
        }
    }
    var seconds: TimeInterval {
        switch self {
        case .oneHour: 3600
        case .sixHours: 6 * 3600
        case .oneDay: 24 * 3600
        }
    }
}

private struct PhotoSlotView: View {
    @Binding var state: PhotoSlotState
    let label: String

    var body: some View {
        PhotosPicker(selection: $state.item, matching: .images) {
            AspectFitTile(cornerRadius: 18, shadow: state.image != nil) {
                if state.image == nil {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .background(Theme.card.clipShape(RoundedRectangle(cornerRadius: 18)))
                }
                if let image = state.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Text("+ \(label)")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.mutedForeground)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .buttonStyle(TileButtonStyle())
        .onChange(of: state.item) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    state.image = uiImage
                }
            }
        }
    }
}
