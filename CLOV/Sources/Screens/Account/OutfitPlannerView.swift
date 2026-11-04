import SwiftUI
import PhotosUI

private struct SavedLook: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var occasion: String
    var itemIDs: [UUID]
    var savedAt: Date = .now
}

struct OutfitPlannerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedIDs = Set<UUID>()
    @State private var lookName = ""
    @State private var occasion = "Everyday"
    @State private var savedLooks: [SavedLook] = []
    @State private var showSavedConfirmation = false
    @State private var selectedCategory: WardrobeCategory?
    @State private var tryOnPhotoItem: PhotosPickerItem?
    @State private var tryOnPhoto: UIImage?
    @State private var tryOnImageURL: String?
    @State private var tryOnJobID: String?
    @State private var tryOnStatus: String?
    @State private var tryOnError: String?
    @State private var isTryingOn = false
    @State private var tryOnTask: Task<Void, Never>?
    @State private var editingLookID: UUID?
    @StateObject private var localWeather = LocalWeatherPromptModel()
    @State private var awaitingWeatherSuggestion = false
    @State private var suggestionNote: String?
    @State private var missingPiecesNotice: String?

    let wardrobeItems: [WardrobeItem]
    private let occasions = ["Everyday", "Work or study", "Dinner", "Event", "Travel"]

    private var storageKey: String { "clov.savedLooks.v1.\(appState.userId.uuidString)" }
    private var selectedItems: [WardrobeItem] { wardrobeItems.filter { selectedIDs.contains($0.id) } }
    private var filteredItems: [WardrobeItem] {
        guard let selectedCategory else { return wardrobeItems.filter { $0.category != WardrobeCategory.other.rawValue } }
        return wardrobeItems.filter { $0.category == selectedCategory.rawValue }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Color.clear.frame(height: 0).id(Self.topAnchorID)
                VStack(alignment: .leading, spacing: 7) {
                    Text("YOUR OUTFIT STUDIO")
                        .font(Theme.micro).tracking(1.3)
                        .foregroundStyle(Theme.accentDeep)
                    Text("Build a look")
                        .font(Theme.editorialFont(size: 34)).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .accessibilityAddTraits(.isHeader)
                    Text("Combine pieces from your wardrobe and create a photo try-on preview.")
                        .font(Theme.bodyEmphasis).foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if wardrobeItems.isEmpty {
                    EmptyStateView(icon: "hanger", title: "Nothing in your wardrobe yet",
                                   message: "Add a few pieces first, and you can start planning outfits here.")
                } else {
                    avatarPreview

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            SectionHeader(title: "Your clothes")
                            Text("\(selectedIDs.count) selected")
                                .font(Theme.label).foregroundStyle(Theme.mutedForeground)
                        }
                        suggestionRow
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                categoryChip("All", isSelected: selectedCategory == nil) { selectedCategory = nil }
                                ForEach(WardrobeCategory.allCases.filter { $0 != .other && $0 != .accessory }) { category in
                                    categoryChip(category.label, isSelected: selectedCategory == category) {
                                        selectedCategory = category
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                            ForEach(filteredItems) { item in
                                itemTile(item)
                            }
                        }
                        if filteredItems.isEmpty {
                            EmptyStateView(icon: "tshirt", title: "Nothing here yet",
                                           message: "No \(selectedCategory?.label.lowercased() ?? "clothes") in your wardrobe yet.")
                                .padding(.vertical, 8)
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            SectionHeader(title: editingLookID == nil ? "Save this look" : "Editing saved look")
                            if editingLookID != nil {
                                Button("Cancel", action: cancelEditing)
                                    .font(Theme.bodyEmphasis).tint(Theme.ink)
                                    .frame(minHeight: Theme.minTapSize)
                                    .accessibilityIdentifier("outfit.cancelEdit")
                            }
                        }
                        if let missingPiecesNotice {
                            Text(missingPiecesNotice)
                                .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
                        }
                        TextField("Give it a name (optional)", text: $lookName)
                            .textFieldStyle(.plain).padding(14).frame(minHeight: Theme.minTapSize)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
                            .accessibilityIdentifier("outfit.lookName")
                        VStack(alignment: .leading, spacing: 7) {
                            Text("OCCASION").font(Theme.micro)
                                .tracking(1.1).foregroundStyle(Theme.mutedForeground)
                            Picker("Occasion", selection: $occasion) {
                                ForEach(occasions, id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.menu).tint(Theme.ink)
                                .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: Theme.minTapSize, alignment: .leading)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
                        }
                        Button(editingLookID == nil ? "Save look" : "Update look", action: saveLook)
                            .buttonStyle(PrimaryButtonStyle(isDisabled: selectedIDs.isEmpty))
                            .disabled(selectedIDs.isEmpty)
                        .accessibilityIdentifier("outfit.saveLook")
                    }
                }

                if !savedLooks.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            SectionHeader(title: "Saved looks")
                            Text("Only you can see these").font(Theme.caption).foregroundStyle(Theme.mutedForeground)
                        }
                        ForEach(savedLooks) { look in savedLookRow(look) }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Outfit planner")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadLooks() }
        .onChange(of: selectedIDs) { _, _ in
            // A job belongs to the clothes it was created with; changing the
            // selection must start a new try-on, not poll the old one.
            resetTryOn()
        }
        .onDisappear { tryOnTask?.cancel() }
        .onChange(of: tryOnPhotoItem) { _, value in
            guard let value else { return }
            Task { await loadTryOnPhoto(value) }
        }
        .alert("Look saved", isPresented: $showSavedConfirmation) {
            Button("Done", role: .cancel) { }
        } message: {
            Text("You can find it in Saved looks on this device.")
        }
        .onChange(of: editingLookID) { _, id in
            guard id != nil else { return }
            withAnimation { proxy.scrollTo(Self.topAnchorID, anchor: .top) }
        }
        }
    }

    private static let topAnchorID = "outfit.top"

    private var suggestionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                // Reuse weather already fetched this session; onChange only fires for new values.
                if let conditions = localWeather.conditions {
                    applySuggestion(for: conditions)
                } else {
                    awaitingWeatherSuggestion = true
                    localWeather.requestWeather()
                }
            } label: {
                Label(localWeather.isLoading ? "Checking the weather…" : "Suggest for today's weather", systemImage: "cloud.sun")
                    .font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16).frame(minHeight: Theme.minTapSize)
                    .background(Theme.muted, in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
                    .contentShape(Capsule(style: .continuous))
            }
            .disabled(localWeather.isLoading)
            .accessibilityIdentifier("outfit.suggest")
            if let note = suggestionNote ?? weatherProblem {
                Text(note).font(Theme.caption).foregroundStyle(Theme.mutedForeground)
            }
        }
        .onChange(of: localWeather.conditions) { _, conditions in
            guard awaitingWeatherSuggestion, let conditions else { return }
            awaitingWeatherSuggestion = false
            applySuggestion(for: conditions)
        }
    }

    private var weatherProblem: String? {
        if localWeather.locationDenied { return "Allow location access in Settings to get weather-based suggestions." }
        return localWeather.errorMessage
    }

    private func applySuggestion(for conditions: LocalWeatherConditions) {
        let picks = WeatherOutfitSuggester.suggest(from: wardrobeItems, weather: conditions)
        guard !picks.isEmpty else {
            suggestionNote = "Nothing in your wardrobe fits \(conditions.summary.lowercased()). Try adding a season to your pieces."
            return
        }
        selectedIDs = Set(picks.map(\.id))
        selectedCategory = nil
        suggestionNote = "Picked \(picks.count) \(picks.count == 1 ? "piece" : "pieces") for \(conditions.summary)."
    }

    private var avatarPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("VIRTUAL TRY-ON").font(Theme.micro).tracking(1.1).foregroundStyle(Theme.mutedForeground)
                    Text("See it on you").font(Theme.title).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                }
                Spacer()
                if isTryingOn { ProgressView().tint(Theme.accentDeep) }
            }

            ZStack {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous).fill(Theme.muted)
                if let tryOnImageURL {
                    RemoteImage(url: tryOnImageURL, label: "AI try-on preview")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped().clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                } else if let tryOnPhoto {
                    Image(uiImage: tryOnPhoto).resizable().scaledToFit()
                        .padding(10).accessibilityLabel("Selected full-body photo")
                } else {
                    VStack(spacing: 9) {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(.largeTitle, design: .rounded, weight: .light)).foregroundStyle(Theme.mutedForeground)
                            .accessibilityHidden(true)
                        Text("Your try-on preview will appear here")
                            .font(Theme.bodyEmphasis).foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
            .frame(maxWidth: .infinity).aspectRatio(0.76, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if tryOnImageURL != nil {
                    Text("AI PREVIEW").font(Theme.micro).tracking(0.8)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(Theme.accentForeground)
                        .background(Theme.accent, in: Capsule(style: .continuous)).padding(10)
                        .accessibilityHidden(true)
                }
            }

            if !selectedItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedItems) { item in
                            HStack(spacing: 7) {
                                RemoteImage(url: item.imageUrl).frame(width: 37, height: 48)
                                    .clipped().clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                                Text(item.name ?? item.subcategory?.capitalized ?? item.category.capitalized)
                                    .font(Theme.caption).lineLimit(1).foregroundStyle(Theme.ink)
                            }
                            .padding(5).padding(.trailing, 7)
                            .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            HStack(spacing: 9) {
                PhotosPicker(selection: $tryOnPhotoItem, matching: .images) {
                    Label(tryOnPhoto == nil ? "Choose full-body photo" : "Change photo", systemImage: "person.crop.rectangle.badge.plus")
                        .font(Theme.label).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.muted, in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
                        .contentShape(Capsule(style: .continuous))
                }
                .accessibilityIdentifier("outfit.chooseTryOnPhoto")

                Button(action: startTryOn) {
                    HStack(spacing: 7) {
                        if isTryingOn { ProgressView().tint(.white) }
                        Text(tryOnJobID == nil ? "Try on" : "Check result")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(isDisabled: !canGenerateTryOn))
                .disabled(!canGenerateTryOn)
                .accessibilityIdentifier("outfit.generateTryOn")
            }

            Text("When you tap Try on, your full-body photo and selected clothing photos are sent to WEARFITS. Its current policy says input images are deleted within 24 hours and generated previews may remain for up to 30 days. Results are images, not an exact-fit guarantee.")
                .font(Theme.microMedium).foregroundStyle(Theme.mutedForeground)
            if let tryOnStatus { Text(tryOnStatus).font(Theme.caption).foregroundStyle(Theme.accentDeep) }
            if let tryOnError { Text(tryOnError).font(Theme.caption).foregroundStyle(Theme.danger) }
        }
        .softCard(radius: Theme.cardRadius, padding: 16)
    }

    private var canGenerateTryOn: Bool {
        !isTryingOn && tryOnPhoto != nil && !selectedIDs.isEmpty
    }

    private func categoryChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(ChipButtonStyle(isSelected: isSelected, font: Theme.label, horizontalPadding: 16))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .motionSafeAnimation(Theme.snap, value: isSelected)
    }

    private func itemTile(_ item: WardrobeItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        let shape = RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
        return Button {
            selectedIDs = OutfitSelection.toggling(item, selected: selectedIDs, in: wardrobeItems)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                AspectFitTile(cornerRadius: Theme.smallRadius, shadow: false) {
                    ZStack(alignment: .topTrailing) {
                        RemoteImage(url: item.imageUrl)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(.title3, design: .rounded, weight: .medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(isSelected ? Theme.accent : .white, isSelected ? Theme.accentForeground : .white.opacity(0.95))
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .padding(8)
                            .accessibilityHidden(true)
                    }
                }
                Text(displayName(item))
                    .font(Theme.label).foregroundStyle(isSelected ? Theme.accentDeep : Theme.ink).lineLimit(1)
            }
            .padding(8)
            .background(isSelected ? Theme.accentTint : Theme.cardElevated, in: shape)
            .overlay(shape.stroke(Theme.accentDeep, lineWidth: isSelected ? 2 : 0))
            .elevatedShadow()
            .frame(maxWidth: .infinity, alignment: .leading)
            .motionSafeAnimation(Theme.snap, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(displayName(item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("outfit.item.\(item.id.uuidString)")
    }

    private func displayName(_ item: WardrobeItem) -> String {
        item.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? item.subcategory?.capitalized ?? item.category.capitalized
    }

    private func savedLookRow(_ look: SavedLook) -> some View {
        let pieces = look.itemIDs.compactMap { id in wardrobeItems.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                Button { openLook(look) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(look.name).font(Theme.headline).foregroundStyle(Theme.ink)
                        Text("\(look.occasion) · \(pieces.count) \(pieces.count == 1 ? "piece" : "pieces")")
                            .font(Theme.label).foregroundStyle(Theme.mutedForeground)
                        Text(editingLookID == look.id ? "Editing" : "Tap to edit")
                            .font(Theme.caption).foregroundStyle(Theme.accentDeep)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens this look in the planner")
                .accessibilityIdentifier("outfit.savedLook.\(look.id.uuidString)")
                Button(role: .destructive) { deleteLook(look) } label: {
                    Image(systemName: "trash").font(Theme.label)
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize).contentShape(Rectangle())
                }.accessibilityLabel("Delete \(look.name)")
            }
            if !pieces.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pieces) { item in
                            RemoteImage(url: item.imageUrl).aspectRatio(contentMode: .fill)
                                .frame(width: 70, height: 88).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                        }
                    }
                }
            }
        }
        .softCard(radius: Theme.tileRadius, padding: 14)
    }

    private func saveLook() {
        guard !selectedIDs.isEmpty else { return }
        let fallbackName = "\(occasion) look"
        let name = lookName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = name.isEmpty ? fallbackName : name
        if let editingLookID, let index = savedLooks.firstIndex(where: { $0.id == editingLookID }) {
            savedLooks[index] = SavedLook(id: editingLookID, name: resolvedName, occasion: occasion,
                                          itemIDs: selectedItems.map(\.id), savedAt: savedLooks[index].savedAt)
        } else {
            savedLooks.insert(SavedLook(name: resolvedName, occasion: occasion,
                                        itemIDs: selectedItems.map(\.id)), at: 0)
        }
        persistLooks()
        clearEditor()
        showSavedConfirmation = true
    }

    /// Loads a saved look back into the planner so it can be adjusted and re-saved.
    private func openLook(_ look: SavedLook) {
        let resolved = OutfitSelection.resolve(look.itemIDs, in: wardrobeItems)
        selectedIDs = resolved.present
        lookName = look.name
        occasion = occasions.contains(look.occasion) ? look.occasion : occasions[0]
        selectedCategory = nil
        editingLookID = look.id
        missingPiecesNotice = resolved.missingCount == 0 ? nil
            : "\(resolved.missingCount) \(resolved.missingCount == 1 ? "piece" : "pieces") from this look \(resolved.missingCount == 1 ? "is" : "are") no longer in your wardrobe."
    }

    private func cancelEditing() { clearEditor() }

    private func clearEditor() {
        selectedIDs.removeAll()
        lookName = ""
        editingLookID = nil
        missingPiecesNotice = nil
    }

    private func deleteLook(_ look: SavedLook) {
        savedLooks.removeAll { $0.id == look.id }
        persistLooks()
        if editingLookID == look.id { clearEditor() }
    }

    private func loadLooks() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            savedLooks = try JSONDecoder().decode([SavedLook].self, from: data)
        } catch {
            Log.app.error("Loading saved looks failed: \(error.localizedDescription)")
        }
    }

    private func persistLooks() {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(savedLooks), forKey: storageKey)
        } catch {
            Log.app.error("Saving looks failed: \(error.localizedDescription)")
        }
    }

    private func loadTryOnPhoto(_ pickerItem: PhotosPickerItem) async {
        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                tryOnError = "Couldn't read that photo. Choose another one."
                return
            }
            tryOnPhoto = image
            resetTryOn()
        } catch {
            tryOnError = "Couldn't load that photo. Choose another one."
        }
    }

    /// Cancels any in-flight try-on and clears its result, so a slow job for
    /// an earlier selection can't land on top of the current outfit.
    private func resetTryOn() {
        tryOnTask?.cancel()
        tryOnTask = nil
        isTryingOn = false
        tryOnJobID = nil
        tryOnImageURL = nil
        tryOnStatus = nil
        tryOnError = nil
    }

    private func startTryOn() {
        tryOnTask = Task { await generateTryOn() }
    }

    private func generateTryOn() async {
        guard !isTryingOn else { return }
        isTryingOn = true
        tryOnError = nil
        // A cancelled run was already reset by resetTryOn(); don't clobber a newer run's flag.
        defer { if !Task.isCancelled { isTryingOn = false } }

        do {
            var response: WardrobeTryOnResponse
            if let jobID = tryOnJobID {
                response = try await API.checkWardrobeTryOn(jobID: jobID)
            } else {
                guard let tryOnPhoto else { return }
                response = try await API.createWardrobeTryOn(photo: tryOnPhoto, itemIDs: selectedItems.map(\.id))
                tryOnJobID = response.jobId
            }

            for _ in 0..<20 where response.imageUrl == nil && response.status != "failed" {
                tryOnStatus = "Fitting your selected clothes…"
                try await Task.sleep(for: .seconds(3))
                response = try await API.checkWardrobeTryOn(jobID: response.jobId)
            }

            guard !Task.isCancelled else { return }
            if let imageURL = response.imageUrl {
                tryOnImageURL = imageURL
                tryOnStatus = "Try-on ready"
            } else if response.status == "failed" {
                tryOnError = response.message ?? "The try-on couldn't be generated. Try another photo or outfit."
                tryOnJobID = nil
            } else {
                tryOnStatus = "Still processing. Tap Check result in a moment."
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            tryOnError = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
