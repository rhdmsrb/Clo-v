import SwiftUI

/// One photo at a time with page dots. Swipe to browse; optionally
/// auto-advances every `CarouselAutoAdvance.interval` seconds until the first
/// tap, horizontal swipe or hold, which stops it for the lifetime of this
/// instance. Vertical scrolling past the carousel does not count.
struct PhotoCarousel: View {
    let urls: [URL]
    @Binding var currentIndex: Int
    var autoAdvance: Bool = false
    /// When true a touch, swipe or hold does not end auto-advance for good; the parent pauses it
    /// (by flipping `autoAdvance`) while a press lasts, and the 3 s timer restarts after each page change.
    var keepsRotatingAfterTouch: Bool = false
    var contentMode: ContentMode = .fill
    var accessibilityIdentifier: String = "photo-carousel"
    /// Called on a tap, from the carousel's own gesture (a parent's tap gesture is not reliably reached through the paged TabView).
    var onTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @State private var logic: CarouselAutoAdvance
    @Environment(\.scenePhase) private var scenePhase
    /// Inactive tabs stay mounted at opacity 0, so `onDisappear` never fires for them.
    @Environment(\.isTabActive) private var isTabActive
    @State private var isOnScreen = false
    @State private var fadingPhoto: URL?
    @State private var fadingOpacity = 0.0

    init(
        urls: [URL],
        currentIndex: Binding<Int>,
        autoAdvance: Bool = false,
        keepsRotatingAfterTouch: Bool = false,
        contentMode: ContentMode = .fill,
        accessibilityIdentifier: String = "photo-carousel",
        onTap: (() -> Void)? = nil
    ) {
        self.urls = urls
        self._currentIndex = currentIndex
        self.autoAdvance = autoAdvance
        self.keepsRotatingAfterTouch = keepsRotatingAfterTouch
        self.contentMode = contentMode
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onTap = onTap
        _logic = State(initialValue: CarouselAutoAdvance(pageCount: urls.count, index: currentIndex.wrappedValue))
    }

    private static let holdDuration: TimeInterval = 0.4
    private static let transitionDuration: TimeInterval = 0.45
    private static let transitionSetupDelay: TimeInterval = 0.05

    private var shouldRun: Bool {
        logic.shouldRun(enabled: autoAdvance, reduceMotion: reduceMotion,
                        isOnScreen: isOnScreen && isTabActive && scenePhase == .active,
                        assistiveTechActive: voiceOverEnabled || switchControlEnabled)
    }

    var body: some View {
        TabView(selection: pageBinding) {
            ForEach(Array(urls.enumerated()), id: \.offset) { offset, url in
                page(url).tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .overlay {
            if let fadingPhoto {
                page(fadingPhoto)
                    .opacity(fadingOpacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) { PageDots(count: urls.count, index: logic.index).padding(.bottom, 10) }
        // Only a tap, a horizontal swipe or a hold counts as interaction. A zero-distance
        // drag would fire on the touch-down of a vertical feed scroll and stop rotation.
        .simultaneousGesture(
            DragGesture(minimumDistance: CarouselAutoAdvance.swipeThreshold)
                .onChanged { if CarouselAutoAdvance.isHorizontalSwipe($0.translation) { stopForGood() } }
        )
        .simultaneousGesture(TapGesture().onEnded { stopForGood(); onTap?() })
        .simultaneousGesture(
            LongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: CarouselAutoAdvance.swipeThreshold)
                .onEnded { _ in stopForGood() }
        )
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        // Re-keyed on `shouldRun`, so leaving the screen or stopping cancels the sleep.
        // A page change (swipe or timer) also re-keys it, so every photo gets a full interval.
        .task(id: "\(shouldRun)-\(logic.index)") { await runTimer() }
        .onChange(of: currentIndex) { _, newValue in
            if newValue != logic.index {
                fadingPhoto = nil
                logic = logic.moved(to: newValue)
            }
        }
        .onChange(of: urls.count) { _, newCount in
            logic = logic.resized(pageCount: newCount)
            if currentIndex != logic.index { currentIndex = logic.index }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel("Photos")
        .accessibilityValue(urls.isEmpty ? "" : "Photo \(logic.index + 1) of \(urls.count)")
        .accessibilityAdjustableAction { direction in
            stopForGood()
            switch direction {
            case .increment: setPage(logic.index + 1)
            case .decrement: setPage(logic.index - 1)
            @unknown default: break
            }
        }
    }

    private var pageBinding: Binding<Int> {
        Binding(
            get: { logic.index },
            set: { newValue in
                // A page change we did not trigger from the timer is a user swipe.
                if newValue != logic.index { stopForGood() }
                setPage(newValue)
            }
        )
    }

    private func setPage(_ newIndex: Int) {
        guard urls.indices.contains(newIndex) else { return }
        fadingPhoto = nil
        logic = logic.moved(to: newIndex)
        currentIndex = newIndex
    }

    private func stopForGood() {
        guard !keepsRotatingAfterTouch, !logic.isStopped else { return }
        fadingPhoto = nil
        logic = logic.userInteracted()
    }

    private func runTimer() async {
        var delay = CarouselAutoAdvance.interval
        while shouldRun, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(delay))
            guard shouldRun, !Task.isCancelled else { return }
            let next = logic.advanced()
            guard urls.indices.contains(logic.index), next.index != logic.index else { continue }
            fadingPhoto = urls[logic.index]
            fadingOpacity = 1
            // The old image stays above the new page, so even the wrap from
            // the last image to the first is a single, gentle transition.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                logic = next
                currentIndex = next.index
            }
            // Give SwiftUI a frame to place the old image before fading it out.
            try? await Task.sleep(for: .seconds(Self.transitionSetupDelay))
            guard shouldRun, !Task.isCancelled else { fadingPhoto = nil; return }
            withAnimation(.easeInOut(duration: Self.transitionDuration)) { fadingOpacity = 0 }
            try? await Task.sleep(for: .seconds(Self.transitionDuration))
            fadingPhoto = nil
            delay = max(0, CarouselAutoAdvance.interval - Self.transitionDuration - Self.transitionSetupDelay)
        }
    }

    private func page(_ url: URL) -> some View {
        Color.clear
            .overlay {
                GeometryReader { proxy in
                    CachedImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: contentMode)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        case .loading:
                            Theme.muted.overlay(ProgressView())
                        case .failure:
                            Theme.muted.overlay(
                                Image(systemName: "photo").foregroundStyle(Theme.mutedForeground)
                            )
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { dot in
                    Circle()
                        .fill(dot == index ? Color.white : Color.white.opacity(0.5))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.28), in: Capsule())
            .motionSafeAnimation(Theme.quick, value: index)
            .accessibilityHidden(true)
        }
    }
}

#Preview("PhotoCarousel") {
    struct Host: View {
        @State var index = 0
        var body: some View {
            PhotoCarousel(
                urls: (1...3).compactMap { URL(string: "https://picsum.photos/seed/clov\($0)/600/800") },
                currentIndex: $index,
                autoAdvance: true
            )
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .padding()
        }
    }
    return Host()
}
