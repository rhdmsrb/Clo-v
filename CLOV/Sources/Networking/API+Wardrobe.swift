import Foundation
import UIKit
import Supabase

extension API {
    // MARK: - Wardrobe

    static func fetchWardrobeItems(ownerId: UUID) async throws -> [WardrobeItem] {
        let rows: [WardrobeItem] = try await client
            .from("wardrobe_items")
            .select()
            .eq("owner_id", value: ownerId)
            .order("created_at", ascending: false)
            .execute()
            .value
        let urls = try await signedStorageURLs(rows.map(\.imageUrl), bucket: "wardrobe-items")
        return rows.map { item in
            var result = item
            result.imageUrl = urls[item.imageUrl] ?? ""
            return result
        }
    }

    static func createWardrobeItem(ownerId: UUID, image: UIImage, name: String?, category: String,
                                   subcategory: String?, color: String?, season: String?, brand: String?,
                                   wearFrequency: String?, tags: [String] = []) async throws {
        let session = try await client.auth.session
        guard session.user.id == ownerId else { throw APIError.message("Please sign in again.") }
        let itemId = UUID()
        let path = try await uploadImage(image, bucket: "wardrobe-items",
                                         pathPrefix: "\(ownerId.storagePathComponent)/\(itemId.storagePathComponent)",
                                         aspectRatio: 3.0 / 4.0, persistPublicURL: false,
                                         preserveAspectRatio: true)
        struct Insert: Encodable {
            let id: UUID; let ownerId: UUID; let imageUrl: String; let name: String?
            let category: String; let subcategory: String?; let color: String?; let season: String?
            let brand: String?; let wearFrequency: String?; let tags: [String]
        }
        do {
            try await client.from("wardrobe_items").insert(Insert(
                id: itemId, ownerId: ownerId, imageUrl: path, name: name,
                category: category, subcategory: subcategory, color: color, season: season,
                brand: brand, wearFrequency: wearFrequency, tags: tags
            )).execute()
        } catch {
            await removeStorageFiles(bucket: "wardrobe-items", paths: [path])
            throw error
        }
    }

    static func updateWardrobeItem(id: UUID, ownerId: UUID, image: UIImage?, name: String?, category: String,
                                   subcategory: String?, color: String?, season: String?, brand: String?,
                                   wearFrequency: String?, tags: [String]) async throws {
        let session = try await client.auth.session
        guard session.user.id == ownerId else { throw APIError.message("Please sign in again.") }
        struct ImageRow: Decodable { let imageUrl: String }
        let existing: [ImageRow] = try await client.from("wardrobe_items")
            .select("image_url").eq("id", value: id).eq("owner_id", value: ownerId).execute().value
        guard let oldImage = existing.first?.imageUrl else { throw APIError.message("This wardrobe item no longer exists.") }
        var newImage: String?
        if let image {
            newImage = try await uploadImage(image, bucket: "wardrobe-items",
                                             pathPrefix: "\(ownerId.storagePathComponent)/\(id.storagePathComponent)",
                                             aspectRatio: 3.0 / 4.0, persistPublicURL: false,
                                             preserveAspectRatio: true)
        }
        struct Update: Encodable {
            let imageUrl: String; let name: String?; let category: String
            let subcategory: String?; let color: String?; let season: String?
            let brand: String?; let wearFrequency: String?; let tags: [String]
        }
        do {
            try await client.from("wardrobe_items").update(Update(
                imageUrl: newImage ?? oldImage, name: name, category: category,
                subcategory: subcategory, color: color, season: season,
                brand: brand, wearFrequency: wearFrequency, tags: tags
            )).eq("id", value: id).eq("owner_id", value: ownerId).execute()
        } catch {
            if let newImage { await removeStorageFiles(bucket: "wardrobe-items", paths: [newImage]) }
            throw error
        }
        if newImage != nil, let oldPath = storagePath(oldImage, bucket: "wardrobe-items") {
            await removeStorageFiles(bucket: "wardrobe-items", paths: [oldPath])
        }
    }

    static func deleteWardrobeItem(id: UUID, ownerId: UUID) async throws {
        let session = try await client.auth.session
        guard session.user.id == ownerId else { throw APIError.message("Please sign in again.") }
        struct ImageRow: Decodable { let imageUrl: String }
        let images: [ImageRow] = try await client.from("wardrobe_items")
            .select("image_url").eq("id", value: id).eq("owner_id", value: ownerId).execute().value
        try await client.from("wardrobe_items").delete()
            .eq("id", value: id).eq("owner_id", value: ownerId).execute()
        let paths = images.compactMap { storagePath($0.imageUrl, bucket: "wardrobe-items") }
        await removeStorageFiles(bucket: "wardrobe-items", paths: paths)
    }
}
