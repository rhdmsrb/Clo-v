import SwiftUI
import PhotosUI

struct WardrobeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [WardrobeItem] = []
    @State private var selectedCategory: WardrobeCategory?
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showAdd = false
    @State private var deleteTarget: WardrobeItem?
    @State private var editTarget: WardrobeItem?

    private var visibleItems: [WardrobeItem] {
        guard let selectedCategory else { return items }
        return items.filter { $0.category == selectedCategory.rawValue }
    }

    private var sections: [(WardrobeCategory, [WardrobeItem])] {
        WardrobeCategory.allCases.compactMap { category in
            let categoryItems = visibleItems.filter { $0.category == category.rawValue }
            return categoryItems.isEmpty ? nil : (category, categoryItems)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("PERSONAL CATALOG").font(.system(.caption2, design: .default).weight(.black)).tracking(1.4).foregroundStyle(Theme.accent)
                        Text("My Wardrobe").font(Theme.editorialFont(size: 42))
                    }
                    Spacer()
                    NavigationLink {
                        ClothingCatalogView()
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44).background(Theme.muted.opacity(0.65))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .accessibilityLabel("Browse clothing catalog")
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .black)).foregroundStyle(Theme.inverseText)
                            .frame(width: 44, height: 44).background(Theme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }.accessibilityLabel("Add wardrobe item")
                }

                NavigationLink {
                    OutfitPlannerView(wardrobeItems: items)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "hanger")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Plan a look").font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text("Put pieces together for what’s coming up")
                                .font(.system(size: 13)).foregroundStyle(Theme.mutedForeground)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 14).padding(.horizontal, 15)
                    .background(Theme.muted.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wardrobe.planLook")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ChipToggle(label: "All", selected: selectedCategory == nil) { selectedCategory = nil }
                        ForEach(WardrobeCategory.allCases) { category in
                            ChipToggle(label: category.label, selected: selectedCategory == category) { selectedCategory = category }
                        }
                    }
                }

                AsyncStateView(isLoading: isLoading, error: error, isEmpty: visibleItems.isEmpty,
                               emptyText: "Your wardrobe is empty. Add your first piece.", topPadding: 36,
                               hasLoaded: hasLoaded, retry: { await load() }) {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(sections, id: \.0) { category, categoryItems in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(category.label.uppercased()).font(.system(.caption2, design: .default).weight(.black)).tracking(1.2)
                                    Spacer(); Text("\(categoryItems.count)").font(.caption2.weight(.bold)).foregroundStyle(Theme.mutedForeground)
                                }
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                                    ForEach(categoryItems) { item in
                                        WardrobeItemCard(item: item,
                                                         onEdit: { editTarget = item },
                                                         onDelete: { deleteTarget = item })
                                    }
                                }
                            }
                        }
                    }
                }
            }.padding(20)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AccountView()
                } label: {
                    AvatarView(url: appState.profile?.avatarUrl,
                               nickname: appState.profile?.nickname,
                               size: 34)
                }
                .accessibilityLabel("Your profile and account settings")
                .accessibilityIdentifier("wardrobe.profile")
            }
        }
        .task(id: appState.contentRevision) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAdd) { AddWardrobeItemView { await load() } }
        .sheet(item: $editTarget) { item in AddWardrobeItemView(item: item) { await load() } }
        .confirmationDialog(
            "Remove this item?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let item = deleteTarget { Task { await delete(item) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove it from your wardrobe.")
        }
    }

    private func load() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do { items = try await API.fetchWardrobeItems(ownerId: appState.userId); hasLoaded = true }
        catch is CancellationError { return }
        catch { self.error = "Couldn't load your wardrobe. Please try again." }
    }

    private func delete(_ item: WardrobeItem) async {
        do { try await API.deleteWardrobeItem(id: item.id, ownerId: appState.userId); items.removeAll { $0.id == item.id }; appState.contentDidChange() }
        catch { self.error = "Couldn't remove this item. Please try again." }
    }
}

private struct WardrobeItemCard: View {
    let item: WardrobeItem
    let onEdit: () -> Void
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AspectFitTile(cornerRadius: 8, shadow: false) {
                    WardrobePhoto(url: item.imageUrl)
                }
                Menu {
                    Button("Edit", action: onEdit)
                    Button("Remove", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .black)).foregroundStyle(Theme.inverseText)
                        .frame(width: 30, height: 30).background(Theme.ink.opacity(0.9)).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }.padding(8).accessibilityLabel("More actions for \(item.name ?? "item")")
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line.opacity(0.25), lineWidth: 1))
            Text((item.name?.isEmpty == false ? item.name! : item.subcategory ?? item.category).uppercased())
                .font(.system(.caption, design: .default).weight(.black)).lineLimit(1)
            HStack(spacing: 4) {
                if let color = item.color, !color.isEmpty { Text(color) }
                if let brand = item.brand, !brand.isEmpty { Text("· \(brand)") }
            }.font(.system(.caption2, design: .default).weight(.medium)).foregroundStyle(Theme.mutedForeground)
            if let tags = item.tags, !tags.isEmpty {
                let credits = tags.filter { $0.hasPrefix("Photo credit:") }
                let styles = tags.filter { !$0.hasPrefix("Photo credit:") }
                if !credits.isEmpty {
                    let details = credits[0].replacingOccurrences(of: "Photo credit: ", with: "").components(separatedBy: "|")
                    HStack(spacing: 7) {
                        Text("Photo · \(details.first ?? "Creator")")
                            .font(.system(size: 10)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                        Spacer(minLength: 2)
                        if details.count > 2, let license = URL(string: details[2]) {
                            Link(details.count > 1 ? details[1] : "License", destination: license)
                                .font(.system(size: 10, weight: .medium))
                        }
                        if details.count > 3, let source = URL(string: details[3]) {
                            Link("Source", destination: source).font(.system(size: 10, weight: .medium))
                        }
                    }
                }
                if !styles.isEmpty {
                    Text(styles.prefix(2).map { "#\($0)" }.joined(separator: "  "))
                    .font(.system(.caption2, design: .default).weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                }
            }
        }
    }
}

/// Keeps every wardrobe photo in the same 3:4 card while showing the full
/// original image. Clothing photos often need more breathing room than a
/// center-cropped social post; fitting the image prevents hems and shoes from
/// disappearing at the edges of the grid.
private struct WardrobePhoto: View {
    let url: String

    var body: some View {
        Group {
            if let imageURL = URL(string: url), !url.isEmpty {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .empty:
                        placeholder(progress: true)
                    case .failure:
                        placeholder(progress: false)
                    @unknown default:
                        placeholder(progress: false)
                    }
                }
            } else {
                placeholder(progress: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.muted)
        .clipped()
    }

    @ViewBuilder
    private func placeholder(progress: Bool) -> some View {
        ZStack {
            Theme.muted
            if progress {
                ProgressView().tint(Theme.mutedForeground)
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AddWardrobeItemView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    let onSaved: () async -> Void
    let item: WardrobeItem?
    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var name = ""
    @State private var category: WardrobeCategory = .top
    @State private var subcategory = ""
    @State private var color = ""
    @State private var season: WardrobeSeason?
    @State private var brand = ""
    @State private var frequency: WardrobeFrequency?
    @State private var tags: Set<String> = []
    @State private var isSaving = false
    @State private var error: String?

    init(item: WardrobeItem? = nil, onSaved: @escaping () async -> Void) {
        self.item = item
        self.onSaved = onSaved
        _name = State(initialValue: item?.name ?? "")
        _category = State(initialValue: item.flatMap { WardrobeCategory(rawValue: $0.category) } ?? .top)
        _subcategory = State(initialValue: item?.subcategory ?? "")
        _color = State(initialValue: item?.color ?? "")
        _season = State(initialValue: item?.season.flatMap(WardrobeSeason.init(rawValue:)))
        _brand = State(initialValue: item?.brand ?? "")
        _frequency = State(initialValue: item?.wearFrequency.flatMap(WardrobeFrequency.init(rawValue:)))
        _tags = State(initialValue: Set(item?.tags ?? []))
    }

    init(initialImage: UIImage, initialName: String, initialCategory: WardrobeCategory,
         initialSubcategory: String, sourceCredit: String, onSaved: @escaping () async -> Void) {
        self.item = nil
        self.onSaved = onSaved
        _image = State(initialValue: initialImage)
        _name = State(initialValue: initialName)
        _category = State(initialValue: initialCategory)
        _subcategory = State(initialValue: initialSubcategory)
        _tags = State(initialValue: [sourceCredit])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(item == nil ? "ADD TO WARDROBE" : "EDIT WARDROBE ITEM")
                        .font(.system(.caption2, design: .default).weight(.black)).tracking(1.5).foregroundStyle(Theme.accent)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack {
                            if let image {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            else if let item { WardrobePhoto(url: item.imageUrl) }
                            else { VStack(spacing: 8) { Image(systemName: "camera.fill").font(.title2); Text("ADD A PHOTO").font(.system(.caption, design: .default).weight(.black)).tracking(1) }.foregroundStyle(Theme.mutedForeground) }
                        }.frame(maxWidth: .infinity).aspectRatio(3.0 / 4.0, contentMode: .fit).background(Theme.muted)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: image == nil ? [6] : [])))
                    }.buttonStyle(TileButtonStyle()).accessibilityLabel(image == nil ? "Add clothing photo" : "Change clothing photo")
                    if tags.contains(where: { $0.hasPrefix("Photo credit:") }) {
                        Label("Creator and license details will stay with this item.", systemImage: "checkmark.seal")
                            .font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                    }
                    LabeledField(label: "NAME (OPTIONAL)", padding: 12) { TextField("Black hoodie", text: $name) }
                    LabeledField(label: "CATEGORY", padding: 12) { Picker("Category", selection: $category) { ForEach(WardrobeCategory.allCases) { Text($0.label).tag($0) } }.pickerStyle(.menu) }
                    HStack(spacing: 10) {
                        LabeledField(label: "TYPE", padding: 12) { TextField("Hoodie", text: $subcategory) }
                        LabeledField(label: "COLOR", padding: 12) { TextField("Black", text: $color) }
                    }
                    HStack(spacing: 10) {
                        LabeledField(label: "SEASON", padding: 12) { Picker("Season", selection: $season) { Text("Any").tag(nil as WardrobeSeason?); ForEach(WardrobeSeason.allCases) { Text($0.label).tag(Optional($0)) } }.pickerStyle(.menu) }
                        LabeledField(label: "BRAND", padding: 12) { TextField("Brand", text: $brand) }
                    }
                    LabeledField(label: "WEAR FREQUENCY", padding: 12) { Picker("Wear frequency", selection: $frequency) { Text("Not set").tag(nil as WardrobeFrequency?); ForEach(WardrobeFrequency.allCases) { Text($0.label).tag(Optional($0)) } }.pickerStyle(.menu) }
                    LabeledField(label: "STYLE TAGS", padding: 10) {
                        FlowLayout(spacing: 7) {
                            ForEach(Self.styleTags, id: \.self) { tag in
                                Button {
                                    if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                                } label: {
                                    Text(tag)
                                        .font(.system(.caption2, design: .default).weight(.bold))
                                        .foregroundStyle(tags.contains(tag) ? Theme.inverseText : Theme.mutedForeground)
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(tags.contains(tag) ? Theme.ink : Theme.muted)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button(isSaving ? "Saving…" : (item == nil ? "Save item" : "Save changes")) { Task { await save() } }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: isSaving)).disabled(isSaving)
                }.padding(20)
            }.background(Theme.background).navigationTitle(item == nil ? "New item" : "Edit item").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onChange(of: photoItem) { _, newItem in
                    Task {
                        guard let newItem,
                              let data = try? await newItem.loadTransferable(type: Data.self),
                              let loaded = UIImage(data: data) else { return }
                        image = loaded
                    }
                }
        }
    }

    private func save() async {
        guard image != nil || item != nil else { self.error = "Add a photo first."; return }
        isSaving = true; error = nil; defer { isSaving = false }
        do {
            if let item {
                try await API.updateWardrobeItem(id: item.id, ownerId: appState.userId, image: image,
                                                 name: name.nilIfBlank, category: category.rawValue,
                                                 subcategory: subcategory.nilIfBlank, color: color.nilIfBlank,
                                                 season: season?.rawValue, brand: brand.nilIfBlank,
                                                 wearFrequency: frequency?.rawValue,
                                                 tags: Array(tags.union((item.tags ?? []).filter { $0.hasPrefix("Photo credit:") })).sorted())
            } else if let image {
                try await API.createWardrobeItem(ownerId: appState.userId, image: image, name: name.nilIfBlank,
                                                 category: category.rawValue, subcategory: subcategory.nilIfBlank,
                                                 color: color.nilIfBlank, season: season?.rawValue, brand: brand.nilIfBlank,
                                                 wearFrequency: frequency?.rawValue, tags: tags.sorted())
            }
            appState.contentDidChange(); Haptics.success(); await onSaved(); dismiss()
        } catch { Haptics.error(); self.error = "Couldn't save this item. Please try again." }
    }

    private static let styleTags = ["Casual", "Minimal", "Streetwear", "Vintage", "Workwear", "Sporty", "Smart casual", "Monochrome", "Statement"]
}

private extension String {
    var nilIfBlank: String? { let value = trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value }
}
