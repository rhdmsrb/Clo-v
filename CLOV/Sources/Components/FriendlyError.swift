import Foundation

/// Message safe to show in the UI. Only errors we authored (`APIError`) are
/// surfaced verbatim; everything else (transport, decoding, backend) falls back
/// to `fallback` so raw `localizedDescription` text never reaches the user.
func friendlyMessage(for error: Error, fallback: String) -> String {
    (error as? APIError)?.errorDescription ?? fallback
}
