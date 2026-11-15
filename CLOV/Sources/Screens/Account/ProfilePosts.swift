import Foundation
import CoreGraphics

/// My-votes row shape — needs `status` and a position-1 thumbnail,
/// which the shared FeedItemDTO doesn't carry.
struct MyFitCheck: Identifiable {
    let id: UUID
    let caption: String?
    let status: String
    var expiresAt: Date? = nil
    let thumbnailURL: String?
}

enum ProfileSegment: String, CaseIterable, Identifiable {
    case live = "Live"
    case ended = "Ended"
    case saved = "Saved"
    var id: String { rawValue }
}

/// Load state of the lazily fetched Saved segment.
enum SavedLoadState: Equatable {
    case notLoaded
    case loaded
    /// Transient (network) failure; worth retrying.
    case failed
    /// The server rejected or can't serve Saved right now.
    case unavailable

    /// Network-level errors are transient; anything else is treated as unavailable.
    static func classify(_ error: Error) -> SavedLoadState {
        error is URLError ? .failed : .unavailable
    }
}

/// Pure profile-grid logic, kept out of the view so it can be unit tested.
enum ProfilePosts {
    /// MyFitCheck carries no photo dimensions, so tiles vary deterministically by index.
    static let tileRatios: [CGFloat] = [0.75, 1.0, 0.7, 0.9, 1.1, 0.8, 0.65, 1.0]

    static func live(_ all: [MyFitCheck], isExpired: (Date?) -> Bool) -> [MyFitCheck] {
        all.filter { $0.status == "live" && !isExpired($0.expiresAt) }
    }

    static func ended(_ all: [MyFitCheck], isExpired: (Date?) -> Bool) -> [MyFitCheck] {
        all.filter { $0.status == "archived" || isExpired($0.expiresAt) }
    }

    static func posts(for segment: ProfileSegment, live: [MyFitCheck], ended: [MyFitCheck], saved: [MyFitCheck]) -> [MyFitCheck] {
        switch segment {
        case .live: live
        case .ended: ended
        case .saved: saved
        }
    }

    /// Keeps the first occurrence of each id, preserving order.
    static func deduplicated(_ posts: [MyFitCheck]) -> [MyFitCheck] {
        var seen = Set<UUID>()
        return posts.filter { seen.insert($0.id).inserted }
    }

    /// Crash-safe even if ids repeat.
    static func ratios(for posts: [MyFitCheck]) -> [UUID: CGFloat] {
        Dictionary(
            posts.enumerated().map { ($1.id, tileRatios[$0 % tileRatios.count]) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func emptyText(for segment: ProfileSegment, saved: SavedLoadState) -> String {
        switch segment {
        case .live: "No live votes yet — post a Fit-Check to get started."
        case .ended: "Completed Fit-Checks will land here."
        case .saved:
            switch saved {
            case .unavailable: "Saved posts aren't available right now."
            case .failed: "Couldn’t load your saved posts."
            case .notLoaded, .loaded: "Posts you save will show up here."
            }
        }
    }
}
