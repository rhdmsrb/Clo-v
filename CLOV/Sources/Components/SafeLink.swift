import Foundation

enum SafeLink {
    /// Parses a remote-supplied string, accepting only `https` URLs with a host
    /// so data from tags or third-party catalogs can't open `tel:`, `sms:` or
    /// other app schemes.
    static func httpsURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }
}
