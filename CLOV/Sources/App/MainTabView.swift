import SwiftUI

private enum Tab {
    case feed, groups, account
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tab: Tab = .feed
    @State private var showCreate = false
    @State private var feedPath = NavigationPath()
    @State private var groupsPath = NavigationPath()

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                NavigationStack(path: $feedPath) { FeedView() }
                    .opacity(tab == .feed ? 1 : 0)
                    .allowsHitTesting(tab == .feed)
                    .accessibilityHidden(tab != .feed)
                NavigationStack(path: $groupsPath) { GroupsView() }
                    .opacity(tab == .groups ? 1 : 0)
                    .allowsHitTesting(tab == .groups)
                    .accessibilityHidden(tab != .groups)
                NavigationStack { AccountView() }
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

    // Four real, equally sized actions keep the bar visually balanced and
    // give every item the same predictable hit area. Posting is an action,
    // so it gets the accent treatment without pretending to be a selected tab.
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.feed, systemImage: "house.fill", label: "Feed")
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("feedTab")
            tabButton(.groups, systemImage: "person.2.fill", label: "Groups")
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("groupsTab")

            createButton
                .frame(maxWidth: .infinity)

            tabButton(.account, systemImage: "person.fill", label: "Me")
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("accountTab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Theme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.line.opacity(0.5), lineWidth: 1)
        }
    }

    private var createButton: some View {
        Button {
            showCreate = true
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.accentForeground)
                    .frame(width: 36, height: 30)
                    .background(Theme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("Post")
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .foregroundStyle(Theme.inverseText)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tabPlusButton")
        .accessibilityLabel("Post a Fit-Check")
    }

    @ViewBuilder
    private func tabButton(_ target: Tab, systemImage: String, label: String) -> some View {
        Button {
            if tab == target {
                resetNavigation(for: target)
            } else {
                withAnimation(Theme.press) { tab = target }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                Text(label).font(.system(size: 10, weight: .bold, design: .default))
            }
            .foregroundStyle(tab == target ? Theme.accent : Theme.inverseText.opacity(0.65))
            .frame(maxWidth: .infinity, minHeight: 48)
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

    private func resetNavigation(for target: Tab) {
        switch target {
        case .feed:
            feedPath = NavigationPath()
        case .groups:
            groupsPath = NavigationPath()
        case .account:
            break
        }
    }
}
