import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tab: MainTab = .feed
    /// Tabs are mounted lazily on first visit so hidden tabs never load data
    /// the user hasn't asked for; once mounted they keep their state.
    @State private var mountedTabs: Set<MainTab> = [.feed]

    /// Measured height of the floating bar (including its outer padding), so
    /// content is inset by the real size rather than a fixed guess.
    @State private var barHeight: CGFloat = 76
    private static let barBottomPadding: CGFloat = 4
    /// Extra scroll room so the last row clears the bar's shadow.
    private static let contentClearance: CGFloat = 12
    @State private var showCreate = false
    /// The bar would otherwise ride above the keyboard and cover results.
    @State private var isKeyboardVisible = false
    @State private var feedPath = NavigationPath()
    @State private var accountPath = NavigationPath()

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                tabRoot(.feed) { NavigationStack(path: $feedPath) { FeedView() } }
                tabRoot(.search) {
                    NavigationStack {
                        SearchExploreView()
                            .navigationDestination(for: FitCheckRoute.self) { route in
                                FitCheckDetailView(fitCheckId: route.id)
                            }
                    }
                }
                tabRoot(.activity) {
                    NavigationStack {
                        NotificationsView(onRead: { appState.contentDidChange() })
                            .navigationDestination(for: FitCheckRoute.self) { route in
                                FitCheckDetailView(fitCheckId: route.id)
                            }
                    }
                }
                tabRoot(.account) { NavigationStack(path: $accountPath) { AccountView() } }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: barHeight + Self.contentClearance) }

            // Capped here, above the bar's @ScaledMetric reads, so its
            // metrics and fonts stop growing together.
            FloatingTabBar(
                selection: tab,
                onSelect: select,
                onCreate: { showCreate = true }
            )
            // Tab labels are caption-sized and share a row of five items, so
            // they collide past xxxLarge; everything else keeps scaling.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .opacity(isKeyboardVisible ? 0 : 1)
            .allowsHitTesting(!isKeyboardVisible)
            .accessibilityHidden(isKeyboardVisible)
            .padding(.horizontal, 20)
            .padding(.bottom, Self.barBottomPadding)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: BarHeightKey.self, value: proxy.size.height)
            })
        }
        // Track the keyboard's real frame: it is on screen while its top edge
        // is above the bottom of the screen, whatever sequence of
        // show/hide/change notifications got it there.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            isKeyboardVisible = endFrame.minY < UIScreen.main.bounds.height
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        // A `clov://vote/<id>` link (see ShareLinkButton / .onOpenURL in
        // CLOVApp) opens here regardless of which tab is active, and
        // regardless of the timer — FitCheckDetailView itself checks
        // expiry and shows VotingEndedView if it's run out. UUID isn't
        // Identifiable, so this is isPresented-driven rather than
        // item-driven; the id is read inside the closure, which only
        // runs while non-nil.
        //
        // One cover for both: two fullScreenCovers on the same view can't
        // reliably present at once. Create wins; the link opens after it closes.
        .fullScreenCover(item: Binding<FullScreenCover?>(
            get: {
                if showCreate { return .create }
                return appState.deepLinkFitCheckId.map(FullScreenCover.vote)
            },
            set: { newValue in
                guard newValue == nil else { return }
                if showCreate { showCreate = false } else { appState.deepLinkFitCheckId = nil }
            }
        )) { cover in
            switch cover {
            case .create:
                CreateFitCheckView()
            case .vote(let id):
                NavigationStack {
                    FitCheckDetailView(fitCheckId: id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { appState.deepLinkFitCheckId = nil }
                            }
                        }
                }
            }
        }
        .onPreferenceChange(BarHeightKey.self) { height in
            if height > 0 { barHeight = height }
        }
        .onChange(of: tab) { _, newTab in
            mountedTabs.insert(newTab)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .task { await premountRemainingTabs() }
        .sensoryFeedback(.selection, trigger: tab)
        .sensoryFeedback(.impact(weight: .medium), trigger: showCreate) { _, new in new }
    }

    private func select(_ target: MainTab) {
        if tab == target {
            resetNavigation(for: target)
        } else {
            tab = target
        }
    }

    /// Builds the other tabs shortly after launch so the first tap on one
    /// doesn't pay for constructing its view tree. Inactive tabs skip data
    /// loading (see `revisionTask`), so this adds no network work.
    private func premountRemainingTabs() async {
        for target in [MainTab.search, .activity, .account] {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            mountedTabs.insert(target)
        }
    }

    private func resetNavigation(for target: MainTab) {
        switch target {
        case .feed: feedPath = NavigationPath()
        case .account: accountPath = NavigationPath()
        case .search, .activity: break
        }
    }

    /// Mounts a tab on first visit and toggles its visibility afterwards.
    @ViewBuilder
    private func tabRoot<Content: View>(_ target: MainTab, @ViewBuilder content: () -> Content) -> some View {
        if mountedTabs.contains(target) {
            content()
                .environment(\.isTabActive, tab == target)
                .environment(\.tabBarClearance, barHeight + Self.contentClearance)
                .tabVisibility(isVisible: tab == target)
        }
    }
}

private extension View {
    func tabVisibility(isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}

extension EnvironmentValues {
    /// Room a tab's scrolling screen must leave so its last row can clear the
    /// floating tab bar. Zero outside the tabs (sheets and full-screen covers).
    @Entry var tabBarClearance: CGFloat = 0
}

private struct BarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum FullScreenCover: Identifiable, Equatable {
    case create
    case vote(UUID)

    var id: String {
        switch self {
        case .create: "create"
        case .vote(let id): "vote-\(id)"
        }
    }
}
