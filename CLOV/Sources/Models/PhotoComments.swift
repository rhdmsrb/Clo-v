import Foundation

/// Which comments the vote screen shows for the photo in the centre of the fan.
enum PhotoComments {
    /// The photo's own comments first (in the order given), then general
    /// comments that were left on the whole Fit-Check without a photo.
    static func visible(_ comments: [CommentDTO], photoId: UUID?) -> [CommentDTO] {
        let own = photoId.map { id in comments.filter { $0.photoId == id } } ?? []
        let general = comments.filter { $0.photoId == nil }
        return own + general
    }

    /// Number of comments tied to exactly this photo (general ones are not counted).
    static func count(_ comments: [CommentDTO], photoId: UUID) -> Int {
        comments.filter { $0.photoId == photoId }.count
    }
}
