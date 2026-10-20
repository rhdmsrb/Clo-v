import ImageIO
import SwiftUI
import UIKit

/// In-memory, downsampled image cache with in-flight de-duplication, so a
/// photo seen once isn't re-downloaded or re-decoded while scrolling back.
final class ImageCache {
    static let shared = ImageCache()

    /// Longest edge, in pixels, that decoded images are reduced to.
    private static let maxPixelSize: CGFloat = 1400
    private static let memoryLimitBytes = 150 * 1024 * 1024

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init() {
        cache.totalCostLimit = Self.memoryLimitBytes
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    /// Signed storage URLs carry a rotating token in the query, so the key is
    /// host + path only; the same object always maps to the same entry.
    static func key(for url: URL) -> String {
        "\(url.host ?? "")\(url.path)"
    }

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: Self.key(for: url) as NSString)
    }

    func image(for url: URL) async -> UIImage? {
        let key = Self.key(for: url)
        if let hit = cache.object(forKey: key as NSString) { return hit }

        let task = loadTask(for: url, key: key)
        let result = await task.value
        lock.withLock { inFlight[key] = nil }
        return result
    }

    /// Returns the running download for `key`, starting one if none exists.
    private func loadTask(for url: URL, key: String) -> Task<UIImage?, Never> {
        lock.withLock {
            if let running = inFlight[key] { return running }
            let task = Task<UIImage?, Never> { [session, cache] in
                guard let (data, response) = try? await session.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let image = Self.downsampled(data) else { return nil }
                cache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
                return image
            }
            inFlight[key] = task
            return task
        }
    }

    /// Starts loading photos ahead of when they're shown (e.g. next feed cards).
    func prefetch(_ urls: [URL]) {
        for url in urls where cachedImage(for: url) == nil {
            Task(priority: .utility) { _ = await image(for: url) }
        }
    }

    private static func downsampled(_ data: Data) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }
}

enum CachedImagePhase { case loading, success(Image), failure }

/// Drop-in replacement for `AsyncImage` that goes through `ImageCache`.
struct CachedImage<Content: View>: View {
    let url: URL
    let content: (CachedImagePhase) -> Content
    @State private var phase: CachedImagePhase

    init(url: URL, @ViewBuilder content: @escaping (CachedImagePhase) -> Content) {
        self.url = url
        self.content = content
        if let hit = ImageCache.shared.cachedImage(for: url) {
            _phase = State(initialValue: .success(Image(uiImage: hit)))
        } else {
            _phase = State(initialValue: .loading)
        }
    }

    var body: some View {
        content(phase)
            .task(id: ImageCache.key(for: url)) {
                if case .success = phase { return }
                if let image = await ImageCache.shared.image(for: url) {
                    phase = .success(Image(uiImage: image))
                } else if !Task.isCancelled {
                    phase = .failure
                }
            }
    }
}
