import SwiftUI

/// Lets the user choose which part of a photo is kept. The photo pans and
/// zooms under a fixed 3:4 frame (the ratio every Fit-Check tile uses) with a
/// rule-of-thirds grid, so what they see is exactly what gets posted.
struct PhotoCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onDone: (UIImage) -> Void

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private static let aspectRatio: CGFloat = 3.0 / 4.0
    private static let maxZoom: CGFloat = 5
    private static let gridLineWidth: CGFloat = 0.5
    private static let frameInset: CGFloat = 20
    private static let dimOpacity: Double = 0.55

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let frame = Self.frameSize(in: proxy.size)
                ZStack {
                    Color.black
                    photo(frame: frame)
                    cropOverlay(frame: frame)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(frame: frame).simultaneously(with: zoomGesture(frame: frame)))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onDone(cropResult(frame: frame)) }.bold()
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Reset") { reset() }
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Crop photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    // MARK: - Layout

    private static func frameSize(in available: CGSize) -> CGSize {
        let maxWidth = max(available.width - frameInset * 2, 1)
        let maxHeight = max(available.height - frameInset * 2 - 60, 1)
        let width = min(maxWidth, maxHeight * aspectRatio)
        return CGSize(width: width, height: width / aspectRatio)
    }

    /// Scale at which the photo exactly covers the frame at zoom 1.
    private func baseScale(frame: CGSize) -> CGFloat {
        max(frame.width / image.size.width, frame.height / image.size.height)
    }

    private func displaySize(frame: CGSize, zoom: CGFloat) -> CGSize {
        let scale = baseScale(frame: frame) * zoom
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private func clamped(_ offset: CGSize, frame: CGSize, zoom: CGFloat) -> CGSize {
        let size = displaySize(frame: frame, zoom: zoom)
        let maxX = max((size.width - frame.width) / 2, 0)
        let maxY = max((size.height - frame.height) / 2, 0)
        return CGSize(width: min(max(offset.width, -maxX), maxX),
                      height: min(max(offset.height, -maxY), maxY))
    }

    // MARK: - Views

    private func photo(frame: CGSize) -> some View {
        let size = displaySize(frame: frame, zoom: zoom)
        return Image(uiImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .offset(offset)
            .accessibilityLabel("Photo to crop")
            .accessibilityHint("Drag to move and pinch to zoom")
    }

    private func cropOverlay(frame: CGSize) -> some View {
        ZStack {
            // Dim everything outside the frame.
            Rectangle()
                .fill(Color.black.opacity(Self.dimOpacity))
                .reverseMask {
                    Rectangle().frame(width: frame.width, height: frame.height)
                }
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: frame.width, height: frame.height)
            thirdsGrid
                .frame(width: frame.width, height: frame.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var thirdsGrid: some View {
        GeometryReader { proxy in
            Path { path in
                for step in 1...2 {
                    let x = proxy.size.width * CGFloat(step) / 3
                    let y = proxy.size.height * CGFloat(step) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.7), lineWidth: Self.gridLineWidth)
        }
    }

    // MARK: - Gestures

    private func dragGesture(frame: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(width: committedOffset.width + value.translation.width,
                                      height: committedOffset.height + value.translation.height)
                offset = clamped(proposed, frame: frame, zoom: zoom)
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func zoomGesture(frame: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(committedZoom * value.magnification, 1), Self.maxZoom)
                offset = clamped(offset, frame: frame, zoom: zoom)
            }
            .onEnded { _ in
                committedZoom = zoom
                committedOffset = offset
            }
    }

    private func reset() {
        zoom = 1
        committedZoom = 1
        offset = .zero
        committedOffset = .zero
    }

    // MARK: - Result

    /// The frame's region in the photo's own point coordinates.
    private func cropResult(frame: CGSize) -> UIImage {
        let scale = baseScale(frame: frame) * zoom
        let size = displaySize(frame: frame, zoom: zoom)
        let originX = (frame.width - size.width) / 2 + offset.width
        let originY = (frame.height - size.height) / 2 + offset.height
        let rect = CGRect(x: -originX / scale, y: -originY / scale,
                          width: frame.width / scale, height: frame.height / scale)
        return image.cropped(toPoints: rect)
    }
}

private extension View {
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle().overlay(alignment: .center) {
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
