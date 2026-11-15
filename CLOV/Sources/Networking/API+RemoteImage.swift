import UIKit

/// Result of vetting a remote image response before its bytes are trusted.
enum RemoteImageValidation {
    static let maxBytes = 15 * 1_024 * 1_024
    static let requestTimeout: TimeInterval = 20
    static let failureMessage = "Couldn’t load that photo. Please try again."
    static let tooLargeMessage = "That photo is too large to load."

    /// Throws a friendly `APIError.message` when the response should not be used.
    /// `requestedHost` is checked against the final (post-redirect) host.
    static func validate(
        statusCode: Int,
        finalHost: String?,
        requestedHost: String?,
        contentType: String?,
        contentLength: Int64?
    ) throws {
        guard (200..<300).contains(statusCode) else { throw APIError.message(failureMessage) }
        guard let finalHost, let requestedHost,
              finalHost.lowercased() == requestedHost.lowercased() else {
            throw APIError.message(failureMessage)
        }
        guard let contentType, contentType.lowercased().hasPrefix("image/") else {
            throw APIError.message(failureMessage)
        }
        if let contentLength, contentLength > Int64(maxBytes) {
            throw APIError.message(tooLargeMessage)
        }
    }
}

extension API {
    /// Downloads an image the user owns (for example a wardrobe photo) from our
    /// own Supabase storage host over https, with a timeout and a size cap.
    /// Cancellable: cancelling the surrounding Task cancels the transfer.
    static func downloadRemoteImage(from urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == AppConfig.supabaseURL.host?.lowercased() else {
            throw APIError.message(RemoteImageValidation.failureMessage)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = RemoteImageValidation.requestTimeout
        request.cachePolicy = .returnCacheDataElseLoad

        let data: Data
        let response: URLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.message(RemoteImageValidation.failureMessage)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.message(RemoteImageValidation.failureMessage)
        }
        try RemoteImageValidation.validate(
            statusCode: http.statusCode,
            finalHost: http.url?.host,
            requestedHost: url.host,
            contentType: http.value(forHTTPHeaderField: "Content-Type"),
            contentLength: Int64(http.value(forHTTPHeaderField: "Content-Length") ?? "")
        )
        // Content-Length can be absent or wrong, so cap the bytes actually received too.
        guard data.count <= RemoteImageValidation.maxBytes else {
            throw APIError.message(RemoteImageValidation.tooLargeMessage)
        }
        guard let image = UIImage(data: data) else {
            throw APIError.message(RemoteImageValidation.failureMessage)
        }
        return image
    }
}
