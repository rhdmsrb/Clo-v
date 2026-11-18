import ImageIO
import SwiftUI
import UIKit

/// In-memory, downsampled image cache with in-flight de-duplication, so a
/// photo seen once isn't re-downloaded or re-decoded while scrolling back.
final class ImageCache {
    static let shared = ImageCache()

    enum Size: Int {
        case avatar = 256
        case thumbnail = 480
        case standard = 1400
    }
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
        #if DEBUG
        if SampleData.isActive {
            configuration.protocolClasses = [SampleImageURLProtocol.self] + (configuration.protocolClasses ?? [])
        }
        #endif
        session = URLSession(configuration: configuration, delegate: ImageNetworkMetrics(), delegateQueue: nil)
    }

    /// Signed storage URLs carry a rotating token in the query, so the key is
    /// host + path only; the same object always maps to the same entry.
    static func key(for url: URL) -> String {
        "\(url.host ?? "")\(url.path)"
    }

    static func key(for url: URL, size: Size) -> String {
        "\(size.rawValue):\(key(for: url))"
    }

    func cachedImage(for url: URL, size: Size = .standard) -> UIImage? {
        cache.object(forKey: Self.key(for: url, size: size) as NSString)
    }

    func image(for url: URL, size: Size = .standard) async -> UIImage? {
        let key = Self.key(for: url, size: size)
        if let hit = cache.object(forKey: key as NSString) { return hit }
        return await loadTask(for: url, key: key, size: size).value
    }

    /// Returns the running download for `key`, starting one if none exists.
    private func loadTask(for url: URL, key: String, size: Size) -> Task<UIImage?, Never> {
        lock.withLock {
            if let running = inFlight[key] { return running }
            if let hit = cache.object(forKey: key as NSString) { return Task { hit } }
            let task = Task<UIImage?, Never> {
                defer { self.lock.withLock { self.inFlight[key] = nil } }
                let interval = Log.performance.beginInterval("Remote image load", id: Log.performance.makeSignpostID())
                defer { Log.performance.endInterval("Remote image load", interval) }
                guard let (data, response) = try? await session.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                guard let image = Self.downsampled(data, maxPixelSize: size.rawValue) else { return nil }
                cache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
                return image
            }
            inFlight[key] = task
            return task
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

private final class ImageNetworkMetrics: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let bytes = metrics.transactionMetrics
            .filter { $0.resourceFetchType == .networkLoad }
            .reduce(Int64(0)) { $0 + $1.countOfResponseBodyBytesReceived }
        if bytes > 0 {
            Log.performance.emitEvent("Image network bytes", "bytes=\(bytes, privacy: .public)")
        }
    }
}

enum CachedImagePhase { case loading, success(Image), failure }

/// Drop-in replacement for `AsyncImage` that goes through `ImageCache`.
struct CachedImage<Content: View>: View {
    let url: URL
    var size: ImageCache.Size = .standard
    let content: (CachedImagePhase) -> Content
    @State private var phase: CachedImagePhase = .loading
    @State private var phaseKey: String?

    init(url: URL, size: ImageCache.Size = .standard, @ViewBuilder content: @escaping (CachedImagePhase) -> Content) {
        self.url = url
        self.size = size
        self.content = content
    }

    var body: some View {
        let key = ImageCache.key(for: url, size: size)
        let cached = ImageCache.shared.cachedImage(for: url, size: size)
        let currentPhase = cached.map { CachedImagePhase.success(Image(uiImage: $0)) }
            ?? (phaseKey == key ? phase : .loading)
        content(currentPhase)
            .task(id: LoadedImageRequest(url: url, size: size)) {
                if phaseKey == key, case .success = phase { return }
                phaseKey = key
                phase = .loading
                let image = await ImageCache.shared.image(for: url, size: size)
                guard !Task.isCancelled else { return }
                if let image {
                    phase = .success(Image(uiImage: image))
                } else {
                    phase = .failure
                }
            }
    }

    private struct LoadedImageRequest: Equatable {
        let url: URL
        let size: ImageCache.Size
    }
}
