import SwiftUI

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
    @State private var selectedAudience: FitCheckAudience
    @State private var votePrompt = ""
    @State private var votingDuration: VotingDuration = .oneDay
    @State private var loadError: String?
    @State private var submitError: String?
    @State private var wardrobeError: String?
    @State private var isPosting = false
    @State private var isLoadingOptions = false
    @State private var wardrobeItems: [WardrobeItem] = []
    @State private var wardrobeSlotId: UUID?
    @State private var isLoadingWardrobe = false
    @State private var showDropPhotosConfirmation = false

    private static let maxPromptLength = 120
    private static let occasionOptions = ["Everyday", "Work", "Date", "Interview", "Party", "Travel", "Wedding"]

    private var filledSlotCount: Int { slots.filter { $0.image != nil }.count }

    private var canPost: Bool {
        !isPosting && filledSlotCount == photoCount
            && (selectedAudience != .group || selectedGroupId != nil)
    }

    init(preselectedGroup: FashionGroup? = nil, initialOccasion: String? = nil) {
        self.preselectedGroup = preselectedGroup
        self.initialOccasion = initialOccasion
        _occasion = State(initialValue: initialOccasion ?? "")
        _selectedAudience = State(initialValue: preselectedGroup == nil ? .everyone : .group)
        _selectedGroupId = State(initialValue: preselectedGroup?.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    PhotoCountSection(photoCount: photoCount, onSelect: selectPhotoCount)
                    PhotoGridSection(slots: $slots, canUseWardrobe: !wardrobeItems.isEmpty) { wardrobeSlotId = $0 }
                    NoteSection(caption: $caption)
                    PromptSection(
                        votePrompt: $votePrompt,
                        suggestions: Self.promptSuggestions(occasion: occasion),
                        maxLength: Self.maxPromptLength
                    )
                    OccasionSection(occasion: $occasion, options: Self.occasionOptions)
                    VotingWindowSection(votingDuration: $votingDuration)
                    AudienceSection(selectedAudience: $selectedAudience, selectedGroupId: $selectedGroupId, myGroups: myGroups)
                    messages
                    postButton
                }
                .padding(20)
            }
            .background(Theme.background)
            .sheet(isPresented: wardrobeSheetBinding) { wardrobeSheet }
            .confirmationDialog("Remove photos 3 and 4?", isPresented: $showDropPhotosConfirmation, titleVisibility: .visible) {
                Button("Use 2 photos", role: .destructive) { applyPhotoCount(2) }
                Button("Keep 4 photos", role: .cancel) {}
            } message: {
                Text("Switching to 2 photos discards the photos you picked in slots 3 and 4.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isPosting)
                }
            }
            .interactiveDismissDisabled(isPosting)
            .task { await loadOptions() }
            .onChange(of: selectedAudience) { _, audience in
                if audience == .group, selectedGroupId == nil { selectedGroupId = myGroups.first?.id }
                if audience != .group { selectedGroupId = nil }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Post a Fit-Check")
                .font(Theme.editorialFont(size: 38))
                .accessibilityIdentifier("createFitCheckTitle")
                .accessibilityAddTraits(.isHeader)
            Text("Upload 2 or 4 photos and ask people to pick their favorite.")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)
        }
    }

    @ViewBuilder
    private var messages: some View {
        if isLoadingOptions {
            ProgressView("Loading your groups and wardrobe…").font(.footnote)
        }
        if let loadError {
            VStack(alignment: .leading, spacing: 4) {
                Text(loadError).font(.footnote).foregroundStyle(Theme.danger)
                Button("Retry") { Task { await loadOptions() } }
                    .frame(minHeight: 44)
                    .disabled(isLoadingOptions)
            }
        }
        if let submitError {
            Text(submitError).font(.footnote).foregroundStyle(Theme.danger)
        }
    }

    private var postButton: some View {
        Button(isPosting ? "Posting…" : "Post it") { Task { await submit() } }
            .buttonStyle(PrimaryButtonStyle(isDisabled: !canPost))
            .disabled(!canPost)
    }

    private var wardrobeSheetBinding: Binding<Bool> {
        Binding(
            get: { wardrobeSlotId != nil },
            set: { if !$0 { wardrobeSlotId = nil; wardrobeError = nil } }
        )
    }

    @ViewBuilder
    private var wardrobeSheet: some View {
        if let slotId = wardrobeSlotId {
            WardrobePickerView(items: wardrobeItems, isLoading: isLoadingWardrobe, errorMessage: wardrobeError) { item in
                Task { await chooseWardrobeItem(item, forSlot: slotId) }
            }
        }
    }

    // MARK: - Photo count

    private func selectPhotoCount(_ count: Int) {
        guard count != photoCount else { return }
        let dropsPickedPhotos = slots.dropFirst(count).contains { $0.image != nil }
        if dropsPickedPhotos {
            showDropPhotosConfirmation = true
        } else {
            applyPhotoCount(count)
        }
    }

    private func applyPhotoCount(_ count: Int) {
        photoCount = count
        if slots.count < count {
            slots = slots + (slots.count..<count).map { _ in PhotoSlotState() }
        } else {
            slots = Array(slots.prefix(count))
        }
    }

    // MARK: - Loading and posting

    private func loadOptions() async {
        isLoadingOptions = true
        loadError = nil
        defer { isLoadingOptions = false }
        async let groups = API.fetchMyGroups(profileId: appState.userId)
        async let wardrobe = API.fetchWardrobeItems(ownerId: appState.userId)
        var failures: [String] = []
        do { myGroups = try await groups } catch {
            Log.app.error("Load groups failed: \(error.localizedDescription)")
            failures.append("groups")
        }
        do { wardrobeItems = try await wardrobe } catch {
            Log.app.error("Load wardrobe failed: \(error.localizedDescription)")
            failures.append("wardrobe")
        }
        if !failures.isEmpty {
            loadError = "Couldn’t load your \(failures.joined(separator: " or ")). Check your connection and retry."
        }
        // Only fill in a default; never overwrite a choice made while loading.
        if selectedAudience == .group, selectedGroupId == nil { selectedGroupId = myGroups.first?.id }
    }

    private func submit() async {
        submitError = nil
        let images = slots.compactMap(\.image)
        guard images.count == photoCount else {
            submitError = "Upload exactly \(photoCount) photos."
            return
        }
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = votePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        isPosting = true
        defer { isPosting = false }
        do {
            try await API.createFitCheck(
                creatorId: appState.userId,
                caption: trimmedCaption.isEmpty ? nil : trimmedCaption,
                occasion: occasion.isEmpty ? nil : occasion,
                groupId: selectedGroupId,
                audience: selectedAudience.rawValue,
                votePrompt: trimmedPrompt.isEmpty ? nil : trimmedPrompt,
                votingDuration: votingDuration.seconds,
                photos: images
            )
            appState.contentDidChange()
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            submitError = friendlyMessage(for: error, fallback: "Couldn’t post your Fit-Check. Please try again.")
        }
    }

    // Note for backend owner: this downloads the wardrobe image with
    // URLSession.shared directly rather than through an API method.
    private func chooseWardrobeItem(_ item: WardrobeItem, forSlot slotId: UUID) async {
        guard let url = URL(string: item.imageUrl) else { return }
        wardrobeError = nil
        isLoadingWardrobe = true
        defer { isLoadingWardrobe = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data),
                  let index = slots.firstIndex(where: { $0.id == slotId }) else {
                wardrobeError = "Couldn't load that wardrobe photo. Please try again."
                return
            }
            slots[index].image = image
            slots[index].item = nil
            wardrobeSlotId = nil
        } catch {
            wardrobeError = "Couldn't load that wardrobe photo. Please try again."
        }
    }

    private static func promptSuggestions(occasion: String) -> [String] {
        let context = occasion.isEmpty ? "today" : "for \(occasion.lowercased())"
        return ["Which shoes finish this look?", "Which outfit feels right \(context)?", "Which layer works better?"]
    }
}
