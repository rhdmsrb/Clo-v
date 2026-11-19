import SwiftUI

/// Lets the user choose which part of a photo is kept. The photo pans and
/// zooms under a fixed 3:4 frame with a rule-of-thirds grid. Cropping is
/// optional; Done keeps the selected crop.
struct PhotoCropView: View {
    let image: UIImage
    var initialCrop: CGRect? = nil
    let onCancel: () -> Void
    let onDone: (UIImage, CGRect) -> Void

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var isMagnifying = false
    @State private var pinchStartOffset: CGSize = .zero
    @State private var restoredCrop = false

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
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(dragGesture(frame: frame).simultaneously(with: zoomGesture(frame: frame, canvas: proxy.size)))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            let rect = CropGeometry.cropRect(image: image.size, frame: frame, zoom: zoom, offset: offset)
                            onDone(image.cropped(toPoints: rect), rect)
                        }.bold()
                    }
                    ToolbarItem(placement: .bottomBar) {
                        HStack(spacing: 16) {
                            Button("Reset") { reset() }
                            Slider(value: zoomBinding(frame: frame), in: 1...Self.maxZoom)
                                .accessibilityLabel("Crop zoom")
                                .accessibilityValue("\(Int((zoom * 100).rounded())) percent")
                        }
                    }
                }
                .onAppear { restoreCrop(frame: frame) }
            }
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
        CropGeometry.clamped(offset, image: image.size, frame: frame, zoom: zoom)
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
                guard !isMagnifying else { return }
                let proposed = CGSize(width: committedOffset.width + value.translation.width,
                                      height: committedOffset.height + value.translation.height)
                offset = clamped(proposed, frame: frame, zoom: zoom)
            }
            .onEnded { _ in if !isMagnifying { committedOffset = offset } }
    }

    private func zoomGesture(frame: CGSize, canvas: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isMagnifying {
                    isMagnifying = true
                    pinchStartOffset = offset
                }
                let newZoom = min(max(committedZoom * value.magnification, 1), Self.maxZoom)
                let anchor = CGPoint(x: (value.startAnchor.x - 0.5) * canvas.width,
                                     y: (value.startAnchor.y - 0.5) * canvas.height)
                let proposed = CropGeometry.zoomedOffset(pinchStartOffset, anchor: anchor,
                                                         factor: newZoom / committedZoom)
                zoom = newZoom
                offset = clamped(proposed, frame: frame, zoom: newZoom)
            }
            .onEnded { _ in
                committedZoom = zoom
                committedOffset = offset
                isMagnifying = false
            }
    }

    private func zoomBinding(frame: CGSize) -> Binding<CGFloat> {
        Binding(get: { zoom }, set: { value in
            zoom = value
            committedZoom = value
            offset = clamped(offset, frame: frame, zoom: value)
            committedOffset = offset
        })
    }

    private func reset() {
        zoom = 1
        committedZoom = 1
        offset = .zero
        committedOffset = .zero
    }

    private func restoreCrop(frame: CGSize) {
        guard !restoredCrop else { return }
        restoredCrop = true
        guard let initialCrop, initialCrop.width > 0, initialCrop.height > 0 else { return }
        let restored = CropGeometry.transform(for: initialCrop, image: image.size, frame: frame, maxZoom: Self.maxZoom)
        zoom = restored.zoom
        committedZoom = restored.zoom
        offset = restored.offset
        committedOffset = restored.offset
    }
}

enum CropGeometry {
    static func scale(image: CGSize, frame: CGSize, zoom: CGFloat) -> CGFloat {
        max(frame.width / image.width, frame.height / image.height) * zoom
    }

    static func clamped(_ offset: CGSize, image: CGSize, frame: CGSize, zoom: CGFloat) -> CGSize {
        let scale = scale(image: image, frame: frame, zoom: zoom)
        let maxX = max((image.width * scale - frame.width) / 2, 0)
        let maxY = max((image.height * scale - frame.height) / 2, 0)
        return CGSize(width: min(max(offset.width, -maxX), maxX),
                      height: min(max(offset.height, -maxY), maxY))
    }

    static func zoomedOffset(_ offset: CGSize, anchor: CGPoint, factor: CGFloat) -> CGSize {
        CGSize(width: anchor.x + (offset.width - anchor.x) * factor,
               height: anchor.y + (offset.height - anchor.y) * factor)
    }

    static func cropRect(image: CGSize, frame: CGSize, zoom: CGFloat, offset: CGSize) -> CGRect {
        let scale = scale(image: image, frame: frame, zoom: zoom)
        return CGRect(x: (image.width * scale - frame.width) / (2 * scale) - offset.width / scale,
                      y: (image.height * scale - frame.height) / (2 * scale) - offset.height / scale,
                      width: frame.width / scale, height: frame.height / scale)
    }

    static func transform(for rect: CGRect, image: CGSize, frame: CGSize, maxZoom: CGFloat) -> (zoom: CGFloat, offset: CGSize) {
        let base = scale(image: image, frame: frame, zoom: 1)
        let zoom = min(max(frame.width / rect.width / base, 1), maxZoom)
        let scale = base * zoom
        let proposed = CGSize(width: (image.width / 2 - rect.midX) * scale,
                              height: (image.height / 2 - rect.midY) * scale)
        return (zoom, clamped(proposed, image: image, frame: frame, zoom: zoom))
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
