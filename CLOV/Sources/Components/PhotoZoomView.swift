import SwiftUI

struct PhotoZoomView: View {
    let photo: FitCheckPhoto
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var committedScale: CGFloat = 1
    @State private var committedOffset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private static let minScale: CGFloat = 1
    private static let maxScale: CGFloat = 4
    private static let doubleTapScale: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                photoContent(size: geometry.size)
                closeButton
            }
            .accessibilityAddTraits(.isModal)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                .background(Color.white.opacity(0.2), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding()
        .accessibilityLabel("Close enlarged photo")
    }

    private var liveScale: CGFloat { clamped(committedScale * pinch) }

    private func liveOffset(size: CGSize) -> CGSize {
        clampedOffset(
            CGSize(width: committedOffset.width + drag.width, height: committedOffset.height + drag.height),
            scale: liveScale,
            size: size
        )
    }

    @ViewBuilder
    private func photoContent(size: CGSize) -> some View {
        if let imageURL = URL(string: photo.imageUrl), !photo.imageUrl.isEmpty {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                        .accessibilityLabel("Look \(photo.position + 1), enlarged")
                        .accessibilityAddTraits(.isImage)
                        .accessibilityAction(named: "Toggle zoom") { toggleZoom(size: size) }
                case .empty:
                    photoPlaceholder(message: "Loading photo…")
                default:
                    photoPlaceholder(message: "This photo couldn’t be loaded.", announce: true)
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(liveScale)
            .offset(liveOffset(size: size))
            .gesture(panAndZoom(size: size))
            .onTapGesture(count: 2) { toggleZoom(size: size) }
        } else {
            photoPlaceholder(message: "This photo is unavailable.", announce: true)
                .frame(width: size.width, height: size.height)
        }
    }

    private func panAndZoom(size: CGSize) -> some Gesture {
        let magnify = MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in
                let target = clamped(committedScale * value.magnification)
                committedScale = target
                committedOffset = clampedOffset(committedOffset, scale: target, size: size)
            }
        let pan = DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                let proposed = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                committedOffset = clampedOffset(proposed, scale: committedScale, size: size)
            }
        return pan.simultaneously(with: magnify)
    }

    private func clamped(_ value: CGFloat) -> CGFloat { min(max(value, Self.minScale), Self.maxScale) }

    /// Keeps the zoomed photo from being dragged beyond its own edges.
    private func clampedOffset(_ offset: CGSize, scale: CGFloat, size: CGSize) -> CGSize {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func toggleZoom(size: CGSize) {
        let target = committedScale > Self.minScale ? Self.minScale : Self.doubleTapScale
        let offset = clampedOffset(committedOffset, scale: target, size: size)
        withAnimation(Theme.animation(.spring(response: 0.25, dampingFraction: 0.8), reduceMotion: reduceMotion)) {
            committedScale = target
            committedOffset = offset
        }
    }

    private func photoPlaceholder(message: String, announce: Bool = false) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "photo").font(.largeTitle)
            Text(message).font(.subheadline.weight(.medium))
        }
        .foregroundStyle(Color.white.opacity(0.8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear {
            if announce { AccessibilityNotification.Announcement(message).post() }
        }
    }
}
