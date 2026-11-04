import SwiftUI
import PhotosUI

struct WardrobeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [WardrobeItem] = []
    @State private var filter = WardrobeFilter()
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var showAdd = false
    @State private var deleteTarget: WardrobeItem?
    @State private var editTarget: WardrobeItem?

    private var visibleItems: [WardrobeItem] { filter.apply(to: items) }

    private var sections: [(WardrobeCategory, [WardrobeItem])] {
        WardrobeCategory.allCases.compactMap { category in
            let categoryItems = visibleItems.filter { $0.category == category.rawValue }
            return categoryItems.isEmpty ? nil : (category, categoryItems)
        }
    }

    private var emptyText: String {
        filter.isActive ? "No pieces match your search or filters." : "Your wardrobe is empty. Add your first piece."
    }

    private var searchAndFilterBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedForeground)
                    .accessibilityHidden(true)
                TextField("Search name, brand, color or tag", text: $filter.searchText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityIdentifier("wardrobe.search")
                if !filter.searchText.isEmpty {
                    Button { filter.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.mutedForeground)
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 13).frame(minHeight: 44)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip("All", isSelected: filter.category == nil) { filter.category = nil }
                    ForEach(WardrobeCategory.allCases) { category in
                        categoryChip(category.label, isSelected: filter.category == category) { filter.category = category }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                Menu {
                    Picker("Season", selection: $filter.season) {
                        Text("Any season").tag(WardrobeSeason?.none)
                        ForEach(WardrobeSeason.allCases) { Text($0.label).tag(WardrobeSeason?.some($0)) }
                    }
                } label: {
                    menuLabel(icon: "sun.max", title: filter.season?.label ?? "Any season", highlighted: filter.season != nil)
                }
                .accessibilityLabel("Season: \(filter.season?.label ?? "Any")")
                Menu {
                    Picker("Sort", selection: $filter.sort) {
                        ForEach(WardrobeSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    menuLabel(icon: "arrow.up.arrow.down", title: filter.sort.label, highlighted: false)
                }
                .accessibilityLabel("Sort: \(filter.sort.label)")
                Spacer()
                Text("\(visibleItems.count) \(visibleItems.count == 1 ? "piece" : "pieces")")
                    .font(Theme.caption).foregroundStyle(Theme.mutedForeground)
                if filter.isActive {
                    Button("Clear") { filter = WardrobeFilter(sort: filter.sort) }
                        .font(Theme.label).tint(Theme.accentDeep)
                        .frame(minHeight: Theme.minTapSize)
                }
            }
        }
    }

    private func categoryChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(ChipButtonStyle(isSelected: isSelected, font: Theme.label, horizontalPadding: 16))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .motionSafeAnimation(Theme.snap, value: isSelected)
    }

    private func menuLabel(icon: String, title: String, highlighted: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: highlighted ? "checkmark" : icon).accessibilityHidden(true)
            Text(title)
        }
        .font(Theme.label)
        .foregroundStyle(highlighted ? Theme.accentDeep : Theme.ink)
        .padding(.horizontal, 14).frame(minHeight: Theme.minTapSize)
        .background(highlighted ? Theme.accentTint : Theme.muted, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(highlighted ? Theme.accentDeep : Theme.controlBorder, lineWidth: highlighted ? 1.5 : 1))
        .contentShape(Capsule(style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PERSONAL CATALOG").font(Theme.micro).tracking(1.4).foregroundStyle(Theme.accentDeep)
                Text("My Wardrobe")
                    .font(Theme.editorialFont(size: 42))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            NavigationLink {
                ClothingCatalogView()
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
                    .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                    .background(Theme.muted, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Browse clothing catalog")
            Button { showAdd = true } label: {
                Image(systemName: "plus").font(Theme.headline).foregroundStyle(Color.white)
                    .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                    .background(Theme.heroGradient, in: Circle())
                    .contentShape(Circle())
            }.accessibilityLabel("Add wardrobe item")
        }
    }

    private var planLookLink: some View {
        NavigationLink {
            OutfitPlannerView(wardrobeItems: items)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "hanger")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.accentDeep)
                    .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                    .background(Theme.accentTint, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Plan a look").font(Theme.headline)
                        .foregroundStyle(Theme.ink)
                    Text("Put pieces together for what’s coming up")
                        .font(Theme.label).foregroundStyle(Theme.mutedForeground)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(Theme.label).foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
            .elevatedCard(radius: Theme.tileRadius, padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wardrobe.planLook")
    }

    private var itemSections: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(sections, id: \.0) { category, categoryItems in
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        SectionHeader(title: category.label)
                        Text("\(categoryItems.count)").font(Theme.caption).foregroundStyle(Theme.mutedForeground)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        ForEach(categoryItems) { item in
                            WardrobeItemCard(item: item,
                                             onEdit: { editTarget = item },
                                             onDelete: { deleteTarget = item },
                                             onWorn: { Task { await logWear(item) } })
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                planLookLink
                if !items.isEmpty { searchAndFilterBar }

                AsyncStateView(isLoading: isLoading, error: error, isEmpty: visibleItems.isEmpty,
                               emptyText: emptyText, topPadding: 36,
                               hasLoaded: hasLoaded, retry: { await load() },
                               emptyIcon: "hanger",
                               emptyTitle: filter.isActive ? "No matches" : "Your wardrobe is empty",
                               emptyActionTitle: filter.isActive ? nil : "Add a piece",
                               emptyAction: filter.isActive ? nil : { showAdd = true },
                               skeleton: .grid) {
                    itemSections
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
        .revisionTask(appState.contentRevision) { await load() }
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

    private func logWear(_ item: WardrobeItem) async {
        do {
            let result = try await API.logWardrobeWear(itemId: item.id)
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            items[index].wearCount = result.count
            items[index].lastWornAt = result.lastWornAt
            Haptics.success()
        } catch {
            Haptics.error()
            self.error = "Couldn't log that you wore this. Please try again."
        }
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
    let onWorn: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AspectFitTile(cornerRadius: Theme.tileRadius, shadow: false) {
                    WardrobePhoto(url: item.imageUrl)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Photo of \(item.name?.isEmpty == false ? item.name! : item.subcategory ?? item.category)")
                        .accessibilityAddTraits(.isImage)
                }
                Menu {
                    Button("Wore it today", systemImage: "checkmark.circle", action: onWorn)
                    Button("Edit", action: onEdit)
                    Button("Remove", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").font(Theme.label).foregroundStyle(Theme.inverseText)
                        .frame(width: 30, height: 30).background(Theme.ink.opacity(0.9), in: Circle())
                        .frame(width: Theme.minTapSize, height: Theme.minTapSize).contentShape(Circle())
                }.padding(1).accessibilityLabel("More actions for \(item.name ?? "item")")
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            .elevatedShadow()
            Text(item.name?.isEmpty == false ? item.name! : item.subcategory ?? item.category)
                .font(Theme.bodyEmphasis).foregroundStyle(Theme.ink).lineLimit(1)
            if let wearSummary = item.wearSummary {
                Text(wearSummary)
                    .font(Theme.micro).foregroundStyle(Theme.accentDeep)
            }
            HStack(spacing: 4) {
                if let color = item.color, !color.isEmpty { Text(color) }
                if let brand = item.brand, !brand.isEmpty { Text("· \(brand)") }
            }.font(Theme.microMedium).foregroundStyle(Theme.mutedForeground)
            if let tags = item.tags, !tags.isEmpty {
                let credits = tags.filter { $0.hasPrefix("Photo credit:") }
                let styles = tags.filter { !$0.hasPrefix("Photo credit:") }
                if !credits.isEmpty {
                    let details = credits[0].replacingOccurrences(of: "Photo credit: ", with: "").components(separatedBy: "|")
                    HStack(spacing: 7) {
                        Text("Photo · \(details.first ?? "Creator")")
                            .font(Theme.microMedium).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                        Spacer(minLength: 2)
                        if details.count > 2, let license = SafeLink.httpsURL(details[2]) {
                            Link(details.count > 1 ? details[1] : "License", destination: license)
                                .font(Theme.font(.caption2, weight: .medium))
                        }
                        if details.count > 3, let source = SafeLink.httpsURL(details[3]) {
                            Link("Source", destination: source).font(Theme.font(.caption2, weight: .medium))
                        }
                    }
                }
                if !styles.isEmpty {
                    Text(styles.prefix(2).map { "#\($0)" }.joined(separator: "  "))
                    .font(Theme.micro)
                    .foregroundStyle(Theme.accentDeep)
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
                        .font(Theme.micro).tracking(1.5).foregroundStyle(Theme.accentDeep)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack {
                            if let image {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            else if let item { WardrobePhoto(url: item.imageUrl) }
                            else { VStack(spacing: 8) { Image(systemName: "camera.fill").font(.title2); Text("ADD A PHOTO").font(Theme.caption).tracking(1) }.foregroundStyle(Theme.mutedForeground) }
                        }.frame(maxWidth: .infinity).aspectRatio(3.0 / 4.0, contentMode: .fit).background(Theme.muted)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous).stroke(Theme.controlBorder, style: StrokeStyle(lineWidth: 1, dash: image == nil ? [6] : [])))
                    }.buttonStyle(TileButtonStyle()).accessibilityLabel(image == nil ? "Add clothing photo" : "Change clothing photo")
                    if tags.contains(where: { $0.hasPrefix("Photo credit:") }) {
                        Label("Creator and license details will stay with this item.", systemImage: "checkmark.seal")
                            .font(Theme.font(.caption)).foregroundStyle(Theme.mutedForeground)
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
                                Button(tag) {
                                    if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                                }
                                .buttonStyle(ChipButtonStyle(isSelected: tags.contains(tag)))
                                .accessibilityAddTraits(tags.contains(tag) ? .isSelected : [])
                            }
                        }
                    }
                    if let error { Text(error).font(Theme.label).foregroundStyle(Theme.danger) }
                    Button(isSaving ? "Saving…" : (item == nil ? "Save item" : "Save changes")) { Task { await save() } }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: isSaving)).disabled(isSaving)
                }.padding(20)
            }.background(Theme.background).navigationTitle(item == nil ? "New item" : "Edit item").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onChange(of: photoItem) { _, newItem in
                    Task {
                        guard let newItem else { return }
                        do {
                            image = try await newItem.loadImage()
                        } catch {
                            self.error = error.localizedDescription
                        }
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
