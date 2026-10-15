import SwiftUI

private enum Tab {
    case feed, search, activity, account
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tab: Tab = .feed
    @State private var showCreate = false
    @State private var feedPath = NavigationPath()
    @State private var accountPath = NavigationPath()

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                NavigationStack(path: $feedPath) { FeedView() }
                    .opacity(tab == .feed ? 1 : 0)
                    .allowsHitTesting(tab == .feed)
                    .accessibilityHidden(tab != .feed)
                NavigationStack {
                    SearchExploreView()
                        .navigationDestination(for: FitCheckRoute.self) { route in
                            FitCheckDetailView(fitCheckId: route.id)
                        }
                }
                    .opacity(tab == .search ? 1 : 0)
                    .allowsHitTesting(tab == .search)
                    .accessibilityHidden(tab != .search)
                NavigationStack {
                    NotificationsView(onRead: { appState.contentDidChange() })
                        .navigationDestination(for: FitCheckRoute.self) { route in
                            FitCheckDetailView(fitCheckId: route.id)
                        }
                }
                    .opacity(tab == .activity ? 1 : 0)
                    .allowsHitTesting(tab == .activity)
                    .accessibilityHidden(tab != .activity)
                NavigationStack(path: $accountPath) { AccountView() }
                    .opacity(tab == .account ? 1 : 0)
                    .allowsHitTesting(tab == .account)
                    .accessibilityHidden(tab != .account)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) }

            tabBar
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
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
        .sensoryFeedback(.selection, trigger: tab)
        .sensoryFeedback(.impact(weight: .medium), trigger: showCreate) { _, new in new }
    }

    // Keep the core loops visible in one thumb-reachable navigation bar.
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.feed, systemImage: "house", activeSystemImage: "house.fill", label: "For You")
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("feedTab")
            tabButton(.search, systemImage: "magnifyingglass", activeSystemImage: "magnifyingglass", label: "Search")
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("searchTab")

            createButton
                .frame(maxWidth: .infinity)

            tabButton(.activity, systemImage: "heart", activeSystemImage: "heart.fill", label: "Activity")
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("activityTab")

            tabButton(.account, systemImage: "person.crop.circle", activeSystemImage: "person.crop.circle.fill", label: "Profile")
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("accountTab")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }

    private var createButton: some View {
        Button {
            showCreate = true
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundStyle(Theme.iconCoral)
                    .frame(width: 46, height: 40)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: .white.opacity(0.18), radius: 8, y: 4)
                Text("Post")
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tabPlusButton")
        .accessibilityLabel("Post a Fit-Check")
    }

    @ViewBuilder
    private func tabButton(_ target: Tab, systemImage: String, activeSystemImage: String, label: String) -> some View {
        Button {
            if tab == target {
                resetNavigation(for: target)
            } else {
                withAnimation(Theme.press) { tab = target }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab == target ? activeSystemImage : systemImage)
                    .font(.system(size: 20, weight: tab == target ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 36, height: 34)
                    .foregroundStyle(tab == target ? tabTint(target) : .white.opacity(0.62))
                    .background(tab == target ? tabTint(target).opacity(0.18) : .clear, in: Circle())
                Text(label).font(.system(size: 10, weight: tab == target ? .bold : .medium, design: .default))
            }
            .foregroundStyle(.white.opacity(tab == target ? 1 : 0.62))
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // `.combine` alone would fold the SF Symbol's own auto-generated
        // description into the label too (e.g. "two people, Groups")
        // instead of leaving it exactly `label` — pin it explicitly so
        // VoiceOver reads just the tab name, and so tests/automation
        // that look up this button by its plain label keep working.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(tab == target ? .isSelected : [])
    }

    private func tabTint(_ target: Tab) -> Color {
        switch target {
        case .feed: Theme.iconApricot
        case .search: Theme.iconSage
        case .activity: Theme.iconCoral
        case .account: Theme.iconPlum
        }
    }

    private func resetNavigation(for target: Tab) {
        switch target {
        case .feed:
            feedPath = NavigationPath()
        case .search, .activity, .account:
            if target == .account { accountPath = NavigationPath() }
        }
    }
}
