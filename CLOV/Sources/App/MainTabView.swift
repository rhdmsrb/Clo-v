import SwiftUI

private enum Tab: Hashable {
    case feed, search, activity, account
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tab: Tab = .feed
    /// Tabs are mounted lazily on first visit so hidden tabs never load data
    /// the user hasn't asked for; once mounted they keep their state.
    @State private var mountedTabs: Set<Tab> = [.feed]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Measured height of the floating bar (including its outer padding), so
    /// content is inset by the real size rather than a fixed guess.
    @State private var barHeight: CGFloat = 76
    private static let barBottomPadding: CGFloat = 4
    @State private var showCreate = false
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
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: barHeight) }

            // Capped here, above the bar's @ScaledMetric reads, so its
            // metrics and fonts stop growing together.
            FloatingTabBar(
                selection: tab,
                onSelect: select,
                onCreate: { showCreate = true }
            )
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, 20)
            .padding(.bottom, Self.barBottomPadding)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: BarHeightKey.self, value: proxy.size.height)
            })
        }
        .fullScreenCover(isPresented: $showCreate) {
            CreateFitCheckView()
        }
        // A `clov://vote/<id>` link (see ShareLinkButton / .onOpenURL in
        // CLOVApp) opens here regardless of which tab is active, and
        // regardless of the timer — FitCheckDetailView itself checks
        // expiry and shows VotingEndedView if it's run out. UUID isn't
        // Identifiable, so this is isPresented-driven rather than
        // item-driven; the id is read inside the closure, which only
        // runs while non-nil.
        .fullScreenCover(isPresented: Binding(
            get: { appState.deepLinkFitCheckId != nil },
            set: { if !$0 { appState.deepLinkFitCheckId = nil } }
        )) {
            if let id = appState.deepLinkFitCheckId {
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
        .onChange(of: tab) { _, newTab in mountedTabs.insert(newTab) }
        .sensoryFeedback(.selection, trigger: tab)
        .sensoryFeedback(.impact(weight: .medium), trigger: showCreate) { _, new in new }
    }

    private func select(_ target: Tab) {
        if tab == target {
            resetNavigation(for: target)
        } else {
            withAnimation(Theme.animation(Theme.press, reduceMotion: reduceMotion)) { tab = target }
        }
    }

    private func resetNavigation(for target: Tab) {
        switch target {
        case .feed: feedPath = NavigationPath()
        case .account: accountPath = NavigationPath()
        case .search, .activity: break
        }
    }

    /// Mounts a tab on first visit and toggles its visibility afterwards.
    @ViewBuilder
    private func tabRoot<Content: View>(_ target: Tab, @ViewBuilder content: () -> Content) -> some View {
        if mountedTabs.contains(target) {
            content()
                .environment(\.isTabActive, tab == target)
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

private struct BarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Keep the core loops visible in one thumb-reachable navigation bar.
private struct FloatingTabBar: View {
    let selection: Tab
    let onSelect: (Tab) -> Void
    let onCreate: () -> Void

    @ScaledMetric(relativeTo: .body) private var tabIconWidth: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var tabIconHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var tabHitHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var createIconWidth: CGFloat = 46
    @ScaledMetric(relativeTo: .body) private var createIconHeight: CGFloat = 40

    private static let inactiveTabLabelOpacity = 0.62

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.feed, systemImage: "house", activeSystemImage: "house.fill", label: "For You")
                .accessibilityIdentifier("feedTab")
            tabButton(.search, systemImage: "magnifyingglass", activeSystemImage: "magnifyingglass", label: "Search")
                .accessibilityIdentifier("searchTab")

            createButton

            tabButton(.activity, systemImage: "heart", activeSystemImage: "heart.fill", label: "Activity")
                .accessibilityIdentifier("activityTab")

            tabButton(.account, systemImage: "person.crop.circle", activeSystemImage: "person.crop.circle.fill", label: "Profile")
                .accessibilityIdentifier("accountTab")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Theme.tabBarSurface, in: RoundedRectangle(cornerRadius: Theme.barRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.barRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }

    private var createButton: some View {
        Button(action: onCreate) {
            VStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.iconCoral)
                    .frame(width: createIconWidth, height: createIconHeight)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: .white.opacity(0.18), radius: 8, y: 4)
                Text("Post")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: tabHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("tabPlusButton")
        .accessibilityLabel("Post a Fit-Check")
        .accessibilityShowsLargeContentViewer {
            Label("Post a Fit-Check", systemImage: "plus")
        }
    }

    @ViewBuilder
    private func tabButton(_ target: Tab, systemImage: String, activeSystemImage: String, label: String) -> some View {
        let isSelected = selection == target
        Button { onSelect(target) } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? activeSystemImage : systemImage)
                    .font(.title3.weight(isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: tabIconWidth, height: tabIconHeight)
                    .foregroundStyle(isSelected ? tabTint(target) : .white.opacity(Self.inactiveTabLabelOpacity))
                    .background(isSelected ? tabTint(target).opacity(0.18) : .clear, in: Circle())
                Text(label).font(.caption2.weight(isSelected ? .bold : .medium))
            }
            .foregroundStyle(.white.opacity(isSelected ? 1 : Self.inactiveTabLabelOpacity))
            .frame(maxWidth: .infinity, minHeight: tabHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        // `.combine` alone would fold the SF Symbol's own auto-generated
        // description into the label too (e.g. "two people, Groups")
        // instead of leaving it exactly `label` — pin it explicitly so
        // VoiceOver reads just the tab name, and so tests/automation
        // that look up this button by its plain label keep working.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: isSelected ? activeSystemImage : systemImage)
        }
    }

    private func tabTint(_ target: Tab) -> Color {
        switch target {
        case .feed: Theme.iconApricot
        case .search: Theme.iconSage
        case .activity: Theme.iconCoral
        case .account: Theme.iconPlum
        }
    }
}
