import PhotosUI
import SwiftUI
import UIKit

extension PhotosPickerItem {
    /// Loads the picked photo, throwing a user-presentable error instead of
    /// letting an unreadable pick silently do nothing.
    func loadImage() async throws -> UIImage {
        guard let data = try await loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { throw APIError.message("We couldn’t read that photo. Please pick a different one.") }
        return image
    }
}

extension UIImage {
    /// Redraws the image with `.up` orientation so pixel-buffer cropping
    /// below operates on the same coordinates the user actually sees —
    /// camera/library photos often carry non-`.up` orientation metadata.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Center-crops to exactly `targetRatio` (width / height) — this is
    /// what makes the uploaded photo match the grid cell it's shown in,
    /// instead of uploading the original (often differently-shaped) photo
    /// and leaving cropping to whatever view happens to display it later.
    func croppedToAspectRatio(_ targetRatio: CGFloat) -> UIImage {
        let normalized = normalizedOrientation()
        guard let cgImage = normalized.cgImage else { return normalized }

        let currentRatio = normalized.size.width / normalized.size.height
        let cropRect: CGRect
        if currentRatio > targetRatio {
            // Wider than target — crop the sides.
            let newWidth = normalized.size.height * targetRatio
            let x = (normalized.size.width - newWidth) / 2
            cropRect = CGRect(x: x, y: 0, width: newWidth, height: normalized.size.height)
        } else {
            // Taller than target — crop top/bottom.
            let newHeight = normalized.size.width / targetRatio
            let y = (normalized.size.height - newHeight) / 2
            cropRect = CGRect(x: 0, y: y, width: normalized.size.width, height: newHeight)
        }

        let scale = normalized.scale
        let scaledRect = CGRect(
            x: cropRect.origin.x * scale,
            y: cropRect.origin.y * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )
        guard let cropped = cgImage.cropping(to: scaledRect) else { return normalized }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }

    /// Downscales so the longest side is at most `maxDimension` — avoids
    /// uploading full camera-resolution (e.g. 4032×3024) images when the
    /// display size is a few hundred points.
    func resized(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }
        let scaleFactor = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
