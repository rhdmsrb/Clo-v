import SwiftUI

struct CreateFitCheckView: View {
    var preselectedGroup: FashionGroup? = nil
    var initialOccasion: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var appState: AppState

    @State private var model: CreateWizardModel
    @State private var slots: [PhotoSlotState] = [.init(), .init()]
    @State private var votingDuration: VotingDuration = .oneDay
    @State private var myGroups: [FashionGroup] = []
    @State private var loadError: String?
    @State private var submitError: String?
    @State private var wardrobeError: String?
    @State private var isPosting = false
    @State private var uploadedCount = 0
    /// What a failed post left on the server; a retry continues from it instead of re-uploading.
    @State private var postProgress: PostProgress?
    @State private var postNotice: String?
    @State private var isLoadingOptions = false
    @State private var wardrobeItems: [WardrobeItem] = []
    @State private var wardrobeSlotId: UUID?
    @State private var isLoadingWardrobe = false
    @State private var showDropPhotosConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var skippedPhotoDetails = false

    private var photoCount: Int { model.photoCount }

    private var hasContent: Bool {
        model.hasEnteredContent(initialOccasion: initialOccasion)
    }

    init(preselectedGroup: FashionGroup? = nil, initialOccasion: String? = nil) {
        self.preselectedGroup = preselectedGroup
        self.initialOccasion = initialOccasion
        _model = State(initialValue: CreateWizardModel(preselectedGroupId: preselectedGroup?.id, occasion: initialOccasion))
#if DEBUG
        if SampleData.isActive && ProcessInfo.processInfo.arguments.contains("--uiTestCreatePhotos") {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
                UIColor.systemOrange.setFill()
                context.fill(CGRect(x: 150, y: 150, width: 300, height: 500))
            }
            _slots = State(initialValue: [PhotoSlotState(image: image), PhotoSlotState(image: image)])
        }
#endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        stepContent
                        messages
                    }
                    .padding(20)
                }
                .id(progressLabel)
                .scrollDismissesKeyboard(.interactively)
                footer
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: wardrobeSheetBinding) { wardrobeSheet }
            .confirmationDialog("Remove photos 3 and 4?", isPresented: $showDropPhotosConfirmation, titleVisibility: .visible) {
                Button("Use 2 photos", role: .destructive) { applyPhotoCount(2) }
                Button("Keep 4 photos", role: .cancel) {}
            } message: {
                Text("Switching to 2 photos discards the photos you picked in slots 3 and 4.")
            }
            .confirmationDialog("Discard this Fit-Check?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { discardAndDismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Everything you entered will be lost.")
            }
            .interactiveDismissDisabled(isPosting || hasContent)
            .alert("Posted", isPresented: Binding(get: { postNotice != nil }, set: { if !$0 { postNotice = nil; dismiss() } })) {
                Button("OK") {}
            } message: { Text(postNotice ?? "") }
            .task { await loadOptions() }
            // Clears drafts left behind by an earlier interrupted post.
            .task { await API.sweepStaleDrafts(creatorId: appState.userId) }
            .onChange(of: slots.map { $0.image != nil }, initial: true) { _, filled in
                model = model.settingFilledSlots(filled)
            }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button { requestClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                    .contentShape(Rectangle())
            }
            .disabled(isPosting)
            .accessibilityLabel("Close")
            .accessibilityHint(hasContent ? "Asks before discarding what you entered" : "")
            .accessibilityIdentifier("createCloseButton")
            Spacer()
            Text(progressLabel)
                .font(Theme.caption)
                .foregroundStyle(Theme.mutedForeground)
                .accessibilityIdentifier("createStepLabel")
            Spacer()
            Color.clear.frame(width: Theme.minTapSize, height: Theme.minTapSize)
        }
        .padding(.horizontal, 8)
    }

    private var progressLabel: String {
        switch model.step {
        case .photos: "Step 1 of 4"
        case .details: "Step 2 of 4"
        case .photoDetail(let index): "Step 3 of 4 · Photo \(index + 1) of \(photoCount)"
        case .preview: "Step 4 of 4"
        }
    }

    private var stepTitle: String {
        switch model.step {
        case .photos: "Post a Fit-Check"
        case .details: "Details"
        case .photoDetail(let index): "Photo \(index + 1)"
        case .preview: "Preview"
        }
    }

    private var stepSubtitle: String? {
        switch model.step {
        case .photos: "Upload 2 or 4 photos and ask people to pick their favorite."
        case .details: nil
        case .photoDetail: "Optional. This shows under the photo when people vote."
        case .preview: "This is how your Fit-Check will look."
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stepTitle)
                .font(Theme.editorialFont(size: 34, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityIdentifier("createFitCheckTitle")
                .accessibilityAddTraits(.isHeader)
            if let stepSubtitle {
                Text(stepSubtitle).font(Theme.body).foregroundStyle(Theme.mutedForeground)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .photos:
            VStack(alignment: .leading, spacing: 20) {
                PhotoCountSection(photoCount: photoCount, onSelect: selectPhotoCount)
                PhotoGridSection(slots: $slots, canUseWardrobe: !wardrobeItems.isEmpty) { wardrobeSlotId = $0 }
            }
        case .details:
            CreateDetailsStep(model: $model, votingDuration: $votingDuration, myGroups: myGroups)
        case .photoDetail(let index):
            CreatePhotoDetailStep(model: $model, image: slots.indices.contains(index) ? slots[index].image : nil, index: index)
                .id(index)
        case .preview:
            CreatePreviewStep(
                model: model,
                images: slots.compactMap(\.image),
                groupName: myGroups.first { $0.id == model.groupId }?.name,
                votingDuration: votingDuration
            )
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if isPosting {
                ProgressView(value: Double(uploadedCount), total: Double(max(photoCount, 1)))
                    .progressViewStyle(.linear).tint(Theme.accentDeep)
                    .accessibilityLabel("Uploading photo \(min(uploadedCount + 1, photoCount)) of \(photoCount)")
            }
            if model.step == .details {
                Button("Skip photo details and preview") {
                    skippedPhotoDetails = true
                    go(to: .preview)
                }
                .font(Theme.label)
                .foregroundStyle(Theme.accentDeep)
                .frame(minHeight: Theme.minTapSize)
                .disabled(!canNext)
                .accessibilityIdentifier("createSkipPhotoDetails")
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { footerButtons }
            } else {
                HStack(spacing: 12) { footerButtons }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.background.opacity(0.96))
    }

    @ViewBuilder
    private var footerButtons: some View {
        if model.previousStep(before: model.step) != nil {
            Button("Back") {
                if model.step == .preview && skippedPhotoDetails {
                    go(to: .details)
                } else {
                    go(to: model.previousStep(before: model.step))
                }
            }
                .buttonStyle(OutlineButtonStyle())
                .disabled(isPosting)
                .accessibilityIdentifier("createBackButton")
        }
        if case .photoDetail = model.step {
            Button("Skip") { skipPhotoDetail() }
                .buttonStyle(OutlineButtonStyle())
                .accessibilityIdentifier("createSkipButton")
        }
        primaryButton
    }

    @ViewBuilder
    private var primaryButton: some View {
        if model.step == .details {
            Button("Post now") { Task { await submit() } }
                .buttonStyle(OutlineButtonStyle())
                .disabled(!canUpload)
                .accessibilityIdentifier("createQuickPost")
        }
        if model.step == .preview {
            Button { Task { await submit() } } label: {
                if isPosting {
                    HStack(spacing: 8) { ProgressView(); Text(uploadLabel) }
                } else {
                    Text(submitError == nil ? "Upload" : "Retry upload")
                }
            }
            .buttonStyle(PrimaryButtonStyle(isDisabled: !canUpload))
            .disabled(!canUpload)
            .accessibilityIdentifier("createUploadButton")
        } else {
            Button("Next") {
                if model.step == .details { skippedPhotoDetails = false }
                go(to: model.nextStep(after: model.step))
            }
                .buttonStyle(PrimaryButtonStyle(isDisabled: !canNext))
                .disabled(!canNext)
                .accessibilityHint(canNext ? "" : nextHint)
                .accessibilityIdentifier("createNextButton")
        }
    }

    /// "Uploading 2 of 4" once the first photo is stored; "Uploading…" before.
    private var uploadLabel: String {
        uploadedCount > 0 ? "Uploading \(min(uploadedCount + 1, photoCount)) of \(photoCount)" : "Uploading…"
    }

    private var canNext: Bool { model.canAdvance(from: model.step) }
    private var canUpload: Bool { !isPosting && model.canAdvance(from: .preview) }
    private var nextHint: String {
        switch model.step {
        case .photos: "Add all photos to continue"
        case .details: "Choose a group or switch to Everyone"
        default: ""
        }
    }

    // MARK: - Navigation

    private func requestClose() {
        if hasContent { showDiscardConfirmation = true } else { dismiss() }
    }

    /// Abandoning a failed post: remove its draft and photos in the background.
    private func discardAndDismiss() {
        if let abandoned = postProgress {
            let creatorId = appState.userId
            Task.detached { await API.discardProgress(creatorId: creatorId, abandoned) }
            postProgress = nil
        }
        dismiss()
    }

    private func go(to step: CreateWizardStep?) {
        guard let step else { return }
        submitError = nil
        withAnimation(Theme.animation(Theme.snap, reduceMotion: reduceMotion)) { model.step = step }
    }

    private func skipPhotoDetail() {
        guard case .photoDetail(let index) = model.step, model.photoDetails.indices.contains(index) else { return }
        model.photoDetails[index] = PhotoDetail()
        go(to: model.nextStep(after: model.step))
    }

    // MARK: - Sections

    @ViewBuilder
    private var messages: some View {
        if isLoadingOptions && model.step != .preview {
            ProgressView("Loading your groups and wardrobe…").font(Theme.caption)
        }
        if let loadError, model.step == .photos || model.step == .details {
            VStack(alignment: .leading, spacing: 4) {
                Label(loadError, systemImage: "exclamationmark.circle.fill")
                    .font(Theme.caption).foregroundStyle(Theme.danger)
                Button("Retry") { Task { await loadOptions() } }
                    .font(Theme.label)
                    .foregroundStyle(Theme.accentDeep)
                    .frame(minHeight: Theme.minTapSize)
                    .disabled(isLoadingOptions)
            }
        }
        if let submitError {
            Label(submitError, systemImage: "exclamationmark.circle.fill")
                .font(Theme.caption).foregroundStyle(Theme.danger)
                .accessibilityIdentifier("createSubmitError")
        }
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
        model = model.settingPhotoCount(count)
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
        if model.audience == .group, model.groupId == nil { model.groupId = myGroups.first?.id }
    }

    private static let droppedExtrasNotice = "Your Fit-Check is live, but its title, tags and photo details weren’t saved because they aren’t supported yet."

    private func submit() async {
        guard !isPosting else { return }
        submitError = nil
        let images = slots.compactMap(\.image)
        guard images.count == photoCount, model.canAdvance(from: .preview) else {
            submitError = "Upload exactly \(photoCount) photos."
            return
        }
        isPosting = true
        uploadedCount = 0
        defer { isPosting = false }
        // createFitCheck drafts, uploads, then publishes. A failure keeps the draft and the
        // photos already stored, so "Retry upload" only sends what is missing.
        do {
            let result = try await API.createFitCheck(
                creatorId: appState.userId,
                caption: model.trimmedCaption,
                occasion: model.occasion.isEmpty ? nil : model.occasion,
                groupId: model.effectiveGroupId,
                audience: model.audience.rawValue,
                votePrompt: model.trimmedTitle,
                votingDuration: votingDuration.seconds,
                photos: images,
                tags: model.postTags,
                photoDetails: model.photoDetailPayload,
                resuming: postProgress,
                onProgress: { postProgress = $0 },
                onPhotoUploaded: { uploadedCount = $0 }
            )
            appState.contentDidChange()
            Haptics.success()
            if result.droppedExtras { postNotice = Self.droppedExtrasNotice } else { dismiss() }
        } catch {
            Haptics.error()
            submitError = friendlyMessage(for: error, fallback: "Couldn’t post your Fit-Check. Please try again.")
        }
    }

    private static let wardrobeLoadFailure = "Couldn’t load that wardrobe photo. Please try again."

    private func chooseWardrobeItem(_ item: WardrobeItem, forSlot slotId: UUID) async {
        // Ignore a second pick while one is still downloading.
        guard !isLoadingWardrobe else { return }
        wardrobeError = nil
        isLoadingWardrobe = true
        defer { isLoadingWardrobe = false }
        do {
            let image = try await API.downloadRemoteImage(from: item.imageUrl)
            guard let index = slots.firstIndex(where: { $0.id == slotId }) else {
                wardrobeError = Self.wardrobeLoadFailure
                return
            }
            slots[index].image = image
            slots[index].original = image
            slots[index].cropRect = nil
            slots[index].item = nil
            wardrobeSlotId = nil
        } catch is CancellationError {
            return
        } catch {
            wardrobeError = friendlyMessage(for: error, fallback: Self.wardrobeLoadFailure)
        }
    }
}
