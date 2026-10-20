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

    let wardrobeItems: [WardrobeItem]
    private let occasions = ["Everyday", "Work or study", "Dinner", "Event", "Travel"]

    private var storageKey: String { "clov.savedLooks.v1.\(appState.userId.uuidString)" }
    private var selectedItems: [WardrobeItem] { wardrobeItems.filter { selectedIDs.contains($0.id) } }
    private var filteredItems: [WardrobeItem] {
        guard let selectedCategory else { return wardrobeItems.filter { $0.category != WardrobeCategory.other.rawValue } }
        return wardrobeItems.filter { $0.category == selectedCategory.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("YOUR OUTFIT STUDIO")
                        .font(.system(.caption2, design: .default).weight(.bold)).tracking(1.3)
                        .foregroundStyle(Theme.accent)
                    Text("Build a look")
                        .font(Theme.editorialFont(size: 34)).foregroundStyle(Theme.ink)
                    Text("Combine pieces from your wardrobe and create a photo try-on preview.")
                        .font(.system(size: 15)).foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if wardrobeItems.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Nothing in your wardrobe yet")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text("Add a few pieces first, and you can start planning outfits here.")
                            .font(.system(size: 14)).foregroundStyle(Theme.mutedForeground)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.muted.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    avatarPreview

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Your clothes").font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(selectedIDs.count) selected")
                                .font(.system(size: 13)).foregroundStyle(Theme.mutedForeground)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(WardrobeCategory.allCases.filter { $0 != .other && $0 != .accessory }) { category in
                                    ChipToggle(label: category.label, selected: selectedCategory == category) {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 14) {
                            ForEach(filteredItems) { item in
                                itemTile(item)
                            }
                        }
                        if filteredItems.isEmpty {
                            Text("No \(selectedCategory?.label.lowercased() ?? "clothes") in your wardrobe yet.")
                                .font(.system(size: 14)).foregroundStyle(Theme.mutedForeground)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        Text("Save this look").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.ink)
                        TextField("Give it a name (optional)", text: $lookName)
                            .textFieldStyle(.plain).padding(14)
                            .background(Theme.muted.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .accessibilityIdentifier("outfit.lookName")
                        VStack(alignment: .leading, spacing: 7) {
                            Text("OCCASION").font(.system(.caption2, design: .default).weight(.bold))
                                .tracking(1.1).foregroundStyle(Theme.mutedForeground)
                            Picker("Occasion", selection: $occasion) {
                                ForEach(occasions, id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.menu).tint(Theme.ink)
                                .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.muted.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        Button(action: saveLook) {
                            Text("Save look")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.inverseText)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(selectedIDs.isEmpty ? Theme.ink.opacity(0.35) : Theme.ink)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .disabled(selectedIDs.isEmpty)
                        .accessibilityIdentifier("outfit.saveLook")
                    }
                }

                if !savedLooks.isEmpty {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Saved looks").font(.system(size: 21, weight: .semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("Only you can see these").font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
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
            tryOnJobID = nil
            tryOnImageURL = nil
            tryOnStatus = nil
            tryOnError = nil
        }
        .onChange(of: tryOnPhotoItem) { _, value in
            guard let value else { return }
            Task { await loadTryOnPhoto(value) }
        }
        .alert("Look saved", isPresented: $showSavedConfirmation) {
            Button("Done", role: .cancel) { }
        } message: {
            Text("You can find it in Saved looks on this device.")
        }
    }

    private var avatarPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("VIRTUAL TRY-ON").font(.system(.caption2, design: .default).weight(.bold)).tracking(1.1).foregroundStyle(Theme.mutedForeground)
                    Text("See it on you").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                }
                Spacer()
                if isTryingOn { ProgressView().tint(Theme.accent) }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.96, green: 0.95, blue: 0.93))
                if let tryOnImageURL {
                    RemoteImage(url: tryOnImageURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let tryOnPhoto {
                    Image(uiImage: tryOnPhoto).resizable().scaledToFit()
                        .padding(10).accessibilityLabel("Selected full-body photo")
                } else {
                    VStack(spacing: 9) {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 34, weight: .light)).foregroundStyle(Theme.mutedForeground)
                        Text("Your try-on preview will appear here")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
            .frame(maxWidth: .infinity).aspectRatio(0.76, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if tryOnImageURL != nil {
                    Text("AI PREVIEW").font(.system(size: 10, weight: .bold)).tracking(0.8)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.white.opacity(0.92), in: Capsule()).padding(10)
                }
            }

            if !selectedItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedItems) { item in
                            HStack(spacing: 7) {
                                RemoteImage(url: item.imageUrl).frame(width: 37, height: 48)
                                    .clipped().clipShape(RoundedRectangle(cornerRadius: 5))
                                Text(item.name ?? item.subcategory?.capitalized ?? item.category.capitalized)
                                    .font(.system(size: 11, weight: .medium)).lineLimit(1).foregroundStyle(Theme.ink)
                            }
                            .padding(5).padding(.trailing, 7)
                            .background(Theme.muted.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            HStack(spacing: 9) {
                PhotosPicker(selection: $tryOnPhotoItem, matching: .images) {
                    Label(tryOnPhoto == nil ? "Choose full-body photo" : "Change photo", systemImage: "person.crop.rectangle.badge.plus")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Theme.muted.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityIdentifier("outfit.chooseTryOnPhoto")

                Button(action: { Task { await generateTryOn() } }) {
                    HStack(spacing: 7) {
                        if isTryingOn { ProgressView().tint(.white) }
                        Text(tryOnJobID == nil ? "Try on" : "Check result")
                    }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(canGenerateTryOn ? Theme.ink : Theme.ink.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                }
                .disabled(!canGenerateTryOn)
                .accessibilityIdentifier("outfit.generateTryOn")
            }

            Text("When you tap Try on, your full-body photo and selected clothing photos are sent to WEARFITS. Its current policy says input images are deleted within 24 hours and generated previews may remain for up to 30 days. Results are images, not an exact-fit guarantee.")
                .font(.system(size: 11)).foregroundStyle(Theme.mutedForeground)
            if let tryOnStatus { Text(tryOnStatus).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent) }
            if let tryOnError { Text(tryOnError).font(.system(size: 12)).foregroundStyle(.red) }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line.opacity(0.45), lineWidth: 1))
    }

    private var canGenerateTryOn: Bool {
        !isTryingOn && tryOnPhoto != nil && !selectedIDs.isEmpty
    }

    private func itemTile(_ item: WardrobeItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return Button {
            if isSelected {
                selectedIDs.remove(item.id)
            } else {
                let isOnePiece = ["dress", "set"].contains(item.category)
                let isUpperBody = ["top", "outerwear"].contains(item.category)
                let mutuallyExclusive = isOnePiece ? ["dress", "set", "top", "bottom", "outerwear"]
                    : (isUpperBody ? ["dress", "set", "top", "outerwear"]
                       : (item.category == "bottom" ? ["dress", "set", "bottom"] : [item.category]))
                let replacedIDs = wardrobeItems.filter { mutuallyExclusive.contains($0.category) }.map(\.id)
                selectedIDs.subtract(replacedIDs)
                selectedIDs.insert(item.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                AspectFitTile(cornerRadius: 8, shadow: false) {
                    ZStack(alignment: .topTrailing) {
                        RemoteImage(url: item.imageUrl)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 23, weight: .medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(isSelected ? Theme.accent : .white, .white.opacity(0.95))
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .padding(8)
                    }
                }
                Text(item.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                     ?? item.subcategory ?? item.category.capitalized)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
            }
            .padding(5)
            .background(isSelected ? Theme.accent.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Theme.accent.opacity(0.65) : Theme.line.opacity(0.35), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name ?? item.category), \(isSelected ? "selected" : "not selected")")
        .accessibilityIdentifier("outfit.item.\(item.id.uuidString)")
    }

    private func savedLookRow(_ look: SavedLook) -> some View {
        let pieces = look.itemIDs.compactMap { id in wardrobeItems.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(look.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("\(look.occasion) · \(pieces.count) \(pieces.count == 1 ? "piece" : "pieces")")
                        .font(.system(size: 13)).foregroundStyle(Theme.mutedForeground)
                }
                Spacer()
                Button(role: .destructive) { deleteLook(look) } label: {
                    Image(systemName: "trash").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground).frame(width: 34, height: 34)
                }.accessibilityLabel("Delete \(look.name)")
            }
            if !pieces.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pieces) { item in
                            RemoteImage(url: item.imageUrl).aspectRatio(contentMode: .fill)
                                .frame(width: 70, height: 88).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(14).background(Theme.muted.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func saveLook() {
        guard !selectedIDs.isEmpty else { return }
        let fallbackName = "\(occasion) look"
        let name = lookName.trimmingCharacters(in: .whitespacesAndNewlines)
        savedLooks.insert(SavedLook(name: name.isEmpty ? fallbackName : name,
                                    occasion: occasion,
                                    itemIDs: selectedItems.map(\.id)), at: 0)
        persistLooks()
        selectedIDs.removeAll()
        lookName = ""
        showSavedConfirmation = true
    }

    private func deleteLook(_ look: SavedLook) {
        savedLooks.removeAll { $0.id == look.id }
        persistLooks()
    }

    private func loadLooks() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedLook].self, from: data) else { return }
        savedLooks = decoded
    }

    private func persistLooks() {
        guard let data = try? JSONEncoder().encode(savedLooks) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadTryOnPhoto(_ pickerItem: PhotosPickerItem) async {
        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                tryOnError = "Couldn't read that photo. Choose another one."
                return
            }
            tryOnPhoto = image
            tryOnImageURL = nil
            tryOnJobID = nil
            tryOnStatus = nil
            tryOnError = nil
        } catch {
            tryOnError = "Couldn't load that photo. Choose another one."
        }
    }

    private func generateTryOn() async {
        guard !isTryingOn else { return }
        isTryingOn = true
        tryOnError = nil
        defer { isTryingOn = false }

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

            if let imageURL = response.imageUrl {
                tryOnImageURL = imageURL
                tryOnStatus = "Try-on ready"
            } else if response.status == "failed" {
                tryOnError = response.message ?? "The try-on couldn't be generated. Try another photo or outfit."
                tryOnJobID = nil
            } else {
                tryOnStatus = "Still processing. Tap Check result in a moment."
            }
        } catch {
            tryOnError = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
