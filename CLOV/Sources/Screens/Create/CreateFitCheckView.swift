import SwiftUI
import PhotosUI

struct CreateFitCheckView: View {
    var preselectedGroup: FashionGroup? = nil
    var initialOccasion: String? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var slots: [PhotoSlotState] = [.init(), .init()]
    @State private var photoCount = 2
    @State private var caption = ""
    @State private var occasion = ""
    @State private var myGroups: [FashionGroup] = []
    @State private var selectedGroupId: UUID?
    @State private var selectedAudience: FitCheckAudience = .everyone
    @State private var votePrompt = ""
    @State private var votingDuration: VotingDuration = .oneDay
    @State private var error: String?
    @State private var isPosting = false
    @State private var wardrobeItems: [WardrobeItem] = []
    @State private var wardrobeSlotIndex: Int?
    @State private var isLoadingWardrobe = false

    private var canPost: Bool {
        !isPosting && slots.filter { $0.image != nil }.count == photoCount
            && (selectedAudience != .group || selectedGroupId != nil)
    }

    init(preselectedGroup: FashionGroup? = nil, initialOccasion: String? = nil) {
        self.preselectedGroup = preselectedGroup
        self.initialOccasion = initialOccasion
        _occasion = State(initialValue: initialOccasion ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Post a Fit-Check")
                        .font(Theme.editorialFont(size: 38))
                        .accessibilityIdentifier("createFitCheckTitle")
                    Text("Upload 2 or 4 photos and ask people to pick their favorite.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)

                    HStack(spacing: 8) {
                        Text("PHOTOS").font(.system(.caption2).weight(.bold)).foregroundStyle(.secondary)
                        Spacer()
                        ForEach([2, 4], id: \.self) { count in
                            Button("\(count) photos") { photoCount = count }
                                .font(.system(.caption2, design: .default).weight(.bold))
                                .foregroundStyle(photoCount == count ? .white : Theme.mutedForeground)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(photoCount == count ? Theme.accent : Theme.card)
                                .clipShape(Capsule())
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(slots.indices, id: \.self) { i in
                            VStack(spacing: 7) {
                                PhotoSlotView(state: $slots[i], label: "Photo \(i + 1)")
                                Button {
                                    wardrobeSlotIndex = i
                                } label: {
                                    Label("My Wardrobe", systemImage: "hanger")
                                        .font(.system(.caption2, design: .default).weight(.bold))
                                        .foregroundStyle(Theme.accent)
                                }
                                .disabled(wardrobeItems.isEmpty)
                            }
                        }
                    }

                    LabeledField(label: "ADD A NOTE (OPTIONAL)", padding: 8) {
                        TextEditor(text: $caption)
                            .frame(height: 80)
                            .overlay(alignment: .topLeading) {
                                if caption.isEmpty {
                                    Text("Add context about where you're going or what matters to you.")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.mutedForeground)
                                        .padding(.top, 8)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text("WHAT SHOULD PEOPLE HELP YOU DECIDE?")
                            .font(.system(.caption2).weight(.bold)).foregroundStyle(.secondary)
                        TextField("e.g. Which shoes finish this look?", text: $votePrompt, axis: .vertical)
                            .lineLimit(1...2)
                            .font(.subheadline)
                            .padding(12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .onChange(of: votePrompt) { _, value in
                                if value.count > 120 { votePrompt = String(value.prefix(120)) }
                            }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(Self.promptSuggestions(occasion: occasion), id: \.self) { suggestion in
                                    Button(suggestion) { votePrompt = suggestion }
                                        .font(.system(.caption2, design: .default).weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(Theme.iconPlum.opacity(0.11), in: Capsule())
                                }
                            }
                        }
                        Text("Optional. A specific question gets more useful feedback.")
                            .font(.caption2).foregroundStyle(Theme.mutedForeground)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHAT'S THE OCCASION?").font(.system(.caption2).weight(.bold)).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.occasionOptions, id: \.self) { option in
                                    ChipToggle(label: option, selected: occasion == option) { occasion = occasion == option ? "" : option }
                                }
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
                        Text("Voting closes after this. Results remain available to you in Me; the post leaves everyone else's feed.")
                            .font(.caption2)
                            .foregroundStyle(Theme.mutedForeground)
                    }

                    audiencePicker

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }

                    Button(isPosting ? "Posting…" : "Post it") { Task { await submit() } }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: !canPost))
                        .disabled(!canPost)
                }
                .padding(20)
            }
            .background(Theme.background)
            .sheet(
                isPresented: Binding(
                    get: { wardrobeSlotIndex != nil },
                    set: { if !$0 { wardrobeSlotIndex = nil } }
                )
            ) {
                if let index = wardrobeSlotIndex {
                    WardrobePickerView(items: wardrobeItems) { item in
                        Task { await chooseWardrobeItem(item, for: index) }
                    }
                }
            }
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
                async let groups = API.fetchMyGroups(profileId: appState.userId)
                async let wardrobe = API.fetchWardrobeItems(ownerId: appState.userId)
                var loadFailed = false
                do { myGroups = try await groups } catch {
                    Log.app.error("Load groups failed: \(error.localizedDescription)")
                    loadFailed = true
                }
                do { wardrobeItems = try await wardrobe } catch {
                    Log.app.error("Load wardrobe failed: \(error.localizedDescription)")
                    loadFailed = true
                }
                if loadFailed { self.error = "Couldn’t load your groups or wardrobe. Close and reopen to try again." }
                selectedAudience = preselectedGroup == nil ? .everyone : .group
                selectedGroupId = preselectedGroup?.id ?? myGroups.first?.id
            }
            .onChange(of: selectedAudience) { _, audience in
                if audience == .group, selectedGroupId == nil { selectedGroupId = myGroups.first?.id }
                if audience != .group { selectedGroupId = nil }
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
                occasion: occasion.isEmpty ? nil : occasion,
                groupId: selectedGroupId,
                audience: selectedAudience.rawValue,
                votePrompt: votePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : votePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
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

    private func chooseWardrobeItem(_ item: WardrobeItem, for index: Int) async {
        guard let url = URL(string: item.imageUrl) else { return }
        isLoadingWardrobe = true
        defer { isLoadingWardrobe = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data), slots.indices.contains(index) else { return }
            slots[index].image = image
            slots[index].item = nil
            wardrobeSlotIndex = nil
        } catch {
            self.error = "Couldn't load that wardrobe photo. Please try again."
        }
    }
}

private extension CreateFitCheckView {
    var audiencePicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("WHO CAN SEE THIS?")
                .font(.system(.caption2).weight(.bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(FitCheckAudience.allCases) { option in
                    Button {
                        withAnimation(Theme.press) { selectedAudience = option }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: option.symbol).font(.system(size: 15, weight: .semibold))
                            Text(option.title).font(.system(.subheadline, design: .default).weight(.semibold))
                            Spacer(minLength: 0)
                            if selectedAudience == option { Image(systemName: "checkmark.circle.fill") }
                        }
                        .foregroundStyle(selectedAudience == option ? Theme.ink : Theme.mutedForeground)
                        .padding(11)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selectedAudience == option ? Theme.accent.opacity(0.12) : Theme.card,
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(selectedAudience == option ? Theme.accent.opacity(0.55) : Theme.line.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedAudience == option ? .isSelected : [])
                }
            }
            if selectedAudience == .group {
                if myGroups.isEmpty {
                    Text("Create or join a group first to share privately with its members.")
                        .font(.caption).foregroundStyle(Theme.mutedForeground)
                } else {
                    Picker("Choose group", selection: $selectedGroupId) {
                        ForEach(myGroups) { group in Text(group.name).tag(Optional(group.id)) }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Text(selectedAudience.description)
                .font(.caption).foregroundStyle(Theme.mutedForeground)
        }
    }

    static func promptSuggestions(occasion: String) -> [String] {
        let context = occasion.isEmpty ? "today" : "for \(occasion.lowercased())"
        return ["Which shoes finish this look?", "Which outfit feels right \(context)?", "Which layer works better?"]
    }
}

private enum FitCheckAudience: String, CaseIterable, Identifiable {
    case everyone = "public"
    case friends
    case group
    case onlyMe = "private"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyone: "Everyone"
        case .friends: "Friends"
        case .group: "A group"
        case .onlyMe: "Only me"
        }
    }
    var symbol: String {
        switch self {
        case .everyone: "globe"
        case .friends: "person.2"
        case .group: "person.3"
        case .onlyMe: "lock"
        }
    }
    var description: String {
        switch self {
        case .everyone: "Anyone on CLO·V can see and vote."
        case .friends: "Only people you’ve accepted as friends can see and vote."
        case .group: "Only members of the selected group can see and vote."
        case .onlyMe: "Only you can see this Fit-Check. It won’t appear in feeds."
        }
    }
}

private extension CreateFitCheckView {
    static let occasionOptions = ["Everyday", "Work", "Date", "Interview", "Party", "Travel", "Wedding"]
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
                        .font(.system(.caption, design: .default).weight(.bold))
                        .foregroundStyle(Theme.mutedForeground)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .buttonStyle(TileButtonStyle())
        .onChange(of: state.item) { _, newItem in
            Task {
                guard let newItem else { return }
                do {
                    state.image = try await newItem.loadImage()
                } catch {
                    Log.app.error("Photo pick failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

private struct WardrobePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [WardrobeItem]
    let onSelect: (WardrobeItem) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 14) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteImage(url: item.imageUrl)
                                    .aspectRatio(3.0 / 4.0, contentMode: .fill)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text((item.name?.isEmpty == false ? item.name! : item.subcategory ?? item.category).uppercased())
                                    .font(.system(.caption2, design: .default).weight(.black))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Choose from Wardrobe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
