import Foundation

/// Builds and parses Fit-Check share links.
///
/// Only an `https` link on the configured `CLOVShareBaseURL` is shareable in
/// release builds: a `clov://` link does nothing for people without the app,
/// and any other app can register the same custom scheme. Until a web domain
/// (and its apple-app-site-association file) is configured, sharing is hidden.
enum ShareURL {
    static var configuredBase: String? {
        Bundle.main.object(forInfoDictionaryKey: "CLOVShareBaseURL") as? String
    }

    /// The link to share, or nil when sharing is not configured.
    static func make(fitCheckId: UUID, base: String? = configuredBase) -> URL? {
        let id = fitCheckId.uuidString.lowercased()
        if let base, let url = URL(string: base), url.scheme == "https", url.host != nil {
            return url.appending(path: "vote/\(id)")
        }
        #if DEBUG
        return URL(string: "clov://vote/\(id)")
        #else
        return nil
        #endif
    }

    /// The Fit-Check id in `clov://vote/<id>` or `https://<share host>/vote/<id>`.
    static func fitCheckId(from url: URL, base: String? = configuredBase) -> UUID? {
        guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
        if url.scheme == "clov" { return url.host == "vote" ? id : nil }
        guard url.scheme == "https",
              let host = base.flatMap(URL.init(string:))?.host,
              url.host == host,
              url.pathComponents.dropLast().last == "vote"
        else { return nil }
        return id
    }
}
