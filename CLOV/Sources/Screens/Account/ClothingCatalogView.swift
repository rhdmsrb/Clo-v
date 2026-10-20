import SwiftUI

/// Searches Openverse for clothing imagery shared under permissive Creative Commons
/// licenses. Every result keeps its creator, license, and source URL attached when saved.
struct ClothingCatalogView: View {
    @State private var query = "women's blouse shirt clothing"
    @State private var results: [OpenverseImage] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var error: String?
    @State private var selected: OpenverseImage?
    @State private var selectedImage: UIImage?
    @State private var isPreparingImage = false
    @State private var selectedCategory: WardrobeCategory = .top

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A LITTLE MORE TO WEAR")
                        .font(.system(.caption2, design: .default).weight(.black)).tracking(1.3).foregroundStyle(Theme.accent)
                    Text("Clothing catalog")
                        .font(Theme.editorialFont(size: 34))
                    Text("Find a piece and add it to your wardrobe. Photos are credited to their original creators.")
                        .font(.system(size: 14)).foregroundStyle(Theme.mutedForeground)
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedForeground)
                    TextField("Try linen, blazer, sneakers…", text: $query)
                        .submitLabel(.search).onSubmit { selectedCategory = .other; Task { await search() } }
                    Button { Task { await search() } } label: {
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.inverseText).frame(width: 36, height: 36).background(Theme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }.accessibilityLabel("Search clothing catalog")
                }
                .padding(.leading, 13).padding(.trailing, 6).padding(.vertical, 6)
                .background(Theme.muted.opacity(0.55)).clipShape(RoundedRectangle(cornerRadius: 10))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CatalogCategory.allCases) { choice in
                            Button(choice.label) {
                                query = choice.query
                                selectedCategory = choice.category
                                Task { await search() }
                            }
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.muted.opacity(0.65)).clipShape(Capsule())
                        }
                    }
                }

                if isLoading && results.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 44)
                } else if let error {
                    VStack(spacing: 10) {
                        Text(error).font(.system(size: 14)).foregroundStyle(Theme.mutedForeground).multilineTextAlignment(.center)
                        Button("Try again") { Task { await search() } }.buttonStyle(PrimaryButtonStyle())
                    }.frame(maxWidth: .infinity).padding(.vertical, 30)
                } else if hasSearched && results.isEmpty {
                    Text("No clothing photos found. Try another search.")
                        .font(.system(size: 14)).foregroundStyle(Theme.mutedForeground).frame(maxWidth: .infinity).padding(.vertical, 36)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(results) { result in
                            Button { Task { await prepare(result) } } label: {
                                CatalogImageCard(result: result, isPreparing: isPreparingImage && selected?.id == result.id)
                            }.buttonStyle(.plain).disabled(isPreparingImage)
                        }
                    }
                    if isLoading { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 10) }
                }

                Text("Images from Openverse · Filtered to CC0, public domain, CC BY, and CC BY-SA. Check each source page for its license details.")
                    .font(.system(size: 11)).foregroundStyle(Theme.mutedForeground).padding(.top, 4)
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Explore clothes")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !hasSearched { await search() } }
        .sheet(item: $selected) { result in
            if let selectedImage {
                AddWardrobeItemView(initialImage: selectedImage, initialName: result.itemName,
                                    initialCategory: selectedCategory, initialSubcategory: selectedCategory.label,
                                    sourceCredit: result.credit, onSaved: {})
            }
        }
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        isLoading = true; error = nil; hasSearched = true; results = []
        defer { isLoading = false }
        do { results = try await OpenverseCatalog.search(term, category: selectedCategory) }
        catch is CancellationError { return }
        catch { self.error = "The clothing catalog couldn't load. Check your connection and try again." }
    }

    private func prepare(_ result: OpenverseImage) async {
        guard let url = URL(string: result.imageURL) else { return }
        isPreparingImage = true; defer { isPreparingImage = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            selectedImage = image
            selected = result
        } catch { self.error = "This photo couldn't be opened. Try another one." }
    }
}

private struct CatalogImageCard: View {
    let result: OpenverseImage
    let isPreparing: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geometry in
                ZStack {
                    Theme.muted
                    AsyncImage(url: URL(string: result.thumbnailURL)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        } else {
                            Theme.muted.overlay(ProgressView())
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                    if isPreparing { Theme.ink.opacity(0.35).overlay(ProgressView().tint(.white)) }
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.inverseText)
                                .frame(width: 32, height: 32).background(Theme.ink.opacity(0.9)).clipShape(Circle())
                        }.padding(9)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            // Fix the card's width-to-height ratio before the remote image is
            // laid out. Openverse thumbnails have mixed intrinsic dimensions.
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            Text(result.titleText.isEmpty ? "Untitled clothing photo" : result.titleText)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
            Text("\(result.creatorText.isEmpty ? "Creator unknown" : result.creatorText) · \(result.license.uppercased())")
                .font(.system(size: 10)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
            if let url = URL(string: result.licenseURL ?? "") {
                Link("License details", destination: url).font(.system(size: 10, weight: .medium))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Add this credited image to your wardrobe")
    }
}

private struct OpenverseImage: Decodable, Identifiable {
    let id: String
    let title: String?
    let creator: String?
    let license: String
    let licenseVersion: String?
    let licenseURL: String?
    let foreignLandingURL: String?
    let url: String?
    let thumbnail: String
    let tags: [OpenverseTag]?
    var titleText: String { title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    var itemName: String {
        let shortTitle = titleText.components(separatedBy: " / ").first ?? titleText
        return String(shortTitle.prefix(55)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var creatorText: String { creator?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    var imageURL: String { url ?? thumbnail }
    var thumbnailURL: String { thumbnail }
    var credit: String {
        let safeCreator = (creatorText.isEmpty ? "Creator unknown" : creatorText).replacingOccurrences(of: "|", with: " ")
        return "Photo credit: \(safeCreator)|\(license.uppercased())\(licenseVersion.map { " \($0)" } ?? "")|\(licenseURL ?? "https://creativecommons.org/")|\(foreignLandingURL ?? "https://openverse.org/")"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, creator, license, thumbnail, url, tags
        case licenseVersion = "license_version"
        case licenseURL = "license_url"
        case foreignLandingURL = "foreign_landing_url"
    }
}

private struct OpenverseTag: Decodable { let name: String }

private enum CatalogCategory: String, CaseIterable, Identifiable {
    case dresses, tops, denim, outerwear, shoes, accessories
    var id: Self { self }
    var label: String { rawValue.capitalized }
    var category: WardrobeCategory {
        switch self {
        case .dresses: .dress
        case .tops: .top
        case .denim: .bottom
        case .outerwear: .outerwear
        case .shoes: .shoes
        case .accessories: .accessory
        }
    }
    var query: String {
        switch self {
        case .dresses: "woman wearing dress"
        case .tops: "women's blouse shirt clothing"
        case .denim: "woman wearing jeans"
        case .outerwear: "women wearing coat jacket"
        case .shoes: "women shoes product fashion"
        case .accessories: "women handbag accessories fashion"
        }
    }
}

private enum OpenverseCatalog {
    private struct Response: Decodable { let results: [OpenverseImage] }
    static func search(_ query: String, category: WardrobeCategory) async throws -> [OpenverseImage] {
        var components = URLComponents(string: "https://api.openverse.org/v1/images/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "license", value: "cc0,pdm,by,by-sa"),
            // Openverse caps unauthenticated requests at 20 results per page.
            URLQueryItem(name: "page_size", value: "20"),
            URLQueryItem(name: "mature", value: "false")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("CLO-V iOS clothing catalog", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.results.compactMap { result in
            guard let imageURL = URL(string: result.thumbnail), imageURL.scheme?.lowercased() == "https",
                  let directURL = URL(string: result.imageURL), directURL.scheme?.lowercased() == "https" else { return nil }
            let searchableText = ([result.titleText] + (result.tags ?? []).map(\.name)).joined(separator: " ").lowercased()
            let blockedTerms = ["halloween", "sexy", "lingerie", "underwear", "costume", "uniform"]
            guard !blockedTerms.contains(where: { searchableText.contains($0) }) else { return nil }
            let terms: [String]
            switch category {
            case .top: terms = ["shirt", "blouse", "top", "polo"]
            case .bottom: terms = ["jean", "denim", "trouser", "pant", "skirt"]
            case .dress: terms = ["dress", "gown"]
            case .outerwear: terms = ["coat", "jacket", "outerwear"]
            case .shoes: terms = ["shoe", "sneaker", "boot", "heel", "footwear"]
            case .accessory: terms = ["bag", "handbag", "jewelry", "hat", "accessory", "accessories"]
            case .set: terms = ["set", "outfit", "clothing", "clothes"]
            case .other: terms = []
            }
            guard terms.isEmpty || terms.contains(where: { searchableText.contains($0) }) else { return nil }
            return result
        }
    }
}
