import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var localWeather = LocalWeatherPromptModel()

    @State private var items: [FeedItemDTO] = []
    @State private var sort: SortOption = .forYou
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var unreadCount = 0
    @State private var searchText = ""
    @State private var selectedOccasion: String?
    @State private var showChallenge = false
    // Open on the browsable Fit-Check feed. The immersive, one-look-at-a-time
    // reel remains available from the feed's Watch Fit-Checks control.
    @State private var showSwipeFeed = false
    @State private var isSearchExpanded = false
    @State private var followingIDs: Set<UUID> = []
    @State private var friendIDs: Set<UUID> = []
    @State private var loggedImpressions: Set<UUID> = []
    @State private var signalScores: [UUID: Int] = [:]
    @State private var nextOffset = 0
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var searchTask: Task<Void, Never>?
    @State private var loadID = UUID()

    private let pageSize = 24

    private enum SortOption { case forYou, newest, votes }
    private enum FeedMode { case forYou, following }
    @State private var mode: FeedMode = .forYou

    private var emptyFeedText: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedOccasion != nil {
            return "No looks match that. Try another search or occasion."
        }
        return mode == .following
            ? "No looks from your circle yet."
            : "Your feed is waiting for its first look. Post a Fit-Check to get started."
    }

    private var visibleItems: [FeedItemDTO] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = items.filter { item in
            let occasionMatches = selectedOccasion == nil || item.occasion == selectedOccasion
            guard occasionMatches else { return false }
            guard !query.isEmpty else { return true }
            return [item.caption, item.occasion, item.profiles?.nickname]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }
        switch mode {
        case .following:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .forYou:
            break
        }
        switch sort {
        case .forYou:
            let preferences = Set(appState.profile?.stylePreferences.map { $0.lowercased() } ?? [])
            return filtered.sorted { recommendationScore($0, preferences: preferences) > recommendationScore($1, preferences: preferences) }
        case .newest: return filtered.sorted { $0.createdAt > $1.createdAt }
        case .votes: return filtered.sorted { $0.fitCheckVotes.count > $1.fitCheckVotes.count }
        }
    }

    var body: some View {
        Group {
            if showSwipeFeed {
                SwipeFeedView(
                    items: visibleItems,
                    voterId: appState.userId,
                    followingIDs: followingIDs,
                    isFollowingMode: mode == .following,
                    onModeChange: { following in
                        let newMode: FeedMode = following ? .following : .forYou
                        guard mode != newMode else { return }
                        mode = newMode
                        Task { await load() }
                    },
                    onBrowse: { withAnimation(.easeInOut(duration: 0.2)) { showSwipeFeed = false } },
                    onToggleFollow: { creatorId, follow in toggleFollow(creatorId, follow: follow) },
                    onEvent: { item, event in logEvent(item, event: event) }
                )
                .background(.black)
                .ignoresSafeArea()
                .navigationBarHidden(true)
                .navigationDestination(for: FitCheckRoute.self) { route in
                    FitCheckDetailView(fitCheckId: route.id)
                }
                .task(id: appState.contentRevision) { await load() }
                .refreshable { await load() }
            } else {
                editorialFeed
            }
        }
    }

    private var editorialFeed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Text("Discover")
                        .font(Theme.editorialFont(size: 40))
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showSwipeFeed = true }
                    } label: {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.iconCoral)
                            .frame(width: 42, height: 42)
                            .background(Theme.iconCoral.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("Watch Fit-Checks")
                    .accessibilityIdentifier("watchFeedButton")
                    Button { isSearchExpanded.toggle() } label: {
                        Image(systemName: isSearchExpanded ? "xmark" : "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isSearchExpanded ? Theme.iconPlum : Theme.iconSage)
                            .frame(width: 42, height: 42)
                            .background((isSearchExpanded ? Theme.iconPlum : Theme.iconSage).opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel(isSearchExpanded ? "Close search" : "Search Fit-Checks")
                    NavigationLink {
                        NotificationsView(onRead: {
                            Task {
                                unreadCount = (try? await API.fetchUnreadNotificationCount(recipientId: appState.userId)) ?? 0
                            }
                        })
                    } label: {
                        bellIcon
                    }
                }

                DailyChallengeCard(
                    challenge: localWeather.conditions.map(DailyChallenge.forWeather) ?? .today,
                    weather: localWeather.conditions,
                    isWeatherLoading: localWeather.isLoading,
                    locationDenied: localWeather.locationDenied,
                    errorMessage: localWeather.errorMessage,
                    onUseWeather: { localWeather.requestWeather() },
                    onJoin: { showChallenge = true }
                )

                HStack(spacing: 8) {
                    modeChip("For You", .forYou)
                    modeChip("Following", .following)
                    Spacer(minLength: 4)
                    if mode == .forYou {
                        Menu {
                            Button("Recommended", systemImage: "sparkles") { sort = .forYou }
                            Button("Newest", systemImage: "clock") { sort = .newest }
                            Button("Most voted", systemImage: "chart.bar.fill") { sort = .votes }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(Theme.iconPlum)
                                Text(sortTitle)
                            }
                            .font(.system(size: 12, weight: .bold, design: .default))
                            .foregroundStyle(Theme.ink)
                            .padding(.vertical, 10)
                        }
                    }
                }

                if isSearchExpanded {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedForeground)
                        TextField("Search people, looks, occasions", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        occasionChip("All", value: nil)
                        ForEach(Self.occasionOptions, id: \.self) { occasion in
                            occasionChip(occasion, value: occasion)
                        }
                    }
                }

#if DEBUG
                SampleVotingSessionCard()
#endif

                AsyncStateView(isLoading: isLoading, error: error, isEmpty: visibleItems.isEmpty,
                               emptyText: emptyFeedText, topPadding: 40, hasLoaded: hasLoaded, retry: { await load() }) {
                    VStack(spacing: 20) {
                        ForEach(visibleItems) { item in
                            FitCheckCardView(
                                item: item,
                                voterId: appState.userId,
                                isFollowing: followingIDs.contains(item.creatorId),
                                onToggleFollow: { follow in toggleFollow(item.creatorId, follow: follow) }
                            )
                            .onAppear { logImpression(for: item) }
                            .onAppear {
                                if item.id == visibleItems.last?.id {
                                    Task { await loadMoreIfNeeded() }
                                }
                            }
                        }
                        if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                if hasLoaded && visibleItems.isEmpty && canLoadMore {
                    Button("Search older Fit-Checks") { Task { await loadMoreIfNeeded() } }
                        .buttonStyle(OutlineButtonStyle())
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationBarHidden(true)
        .navigationDestination(for: FitCheckRoute.self) { route in
            FitCheckDetailView(fitCheckId: route.id)
        }
        .refreshable { await load() }
        .sheet(isPresented: $showChallenge) {
            CreateFitCheckView(initialOccasion: DailyChallenge.today.occasion)
        }
        .task(id: appState.contentRevision) { await load() }
        .onChange(of: searchText) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await load()
            }
        }
        .onChange(of: selectedOccasion) { _, _ in Task { await load() } }
    }

    private var bellIcon: some View {
        ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(unreadCount > 0 ? Theme.iconCoral : Theme.iconApricot)
                .frame(width: 42, height: 42)
                .background((unreadCount > 0 ? Theme.iconCoral : Theme.iconApricot).opacity(0.12), in: Circle())
            if unreadCount > 0 {
                Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                    .font(.system(size: 9, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Theme.iconCoral)
                    .clipShape(Circle())
                    .offset(x: 4, y: -4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unreadCount > 0 ? "Notifications, \(unreadCount) unread" : "Notifications")
    }

    @ViewBuilder
    private func modeChip(_ label: String, _ option: FeedMode) -> some View {
        Button {
            guard mode != option else { return }
            withAnimation(Theme.press) { mode = option }
            Task { await load() }
        } label: {
            Text(label)
                .font(.system(.subheadline, design: .default).weight(mode == option ? .semibold : .regular))
                .foregroundStyle(mode == option ? Theme.ink : Theme.mutedForeground)
                .padding(.horizontal, 4)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(mode == option ? Theme.accent : .clear)
                        .frame(height: 2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("feedMode_\(label.replacingOccurrences(of: " ", with: ""))")
    }

    @ViewBuilder
    private func occasionChip(_ label: String, value: String?) -> some View {
        Button {
            withAnimation(Theme.press) { selectedOccasion = value }
        } label: {
            Text(label)
                .font(.system(.caption, design: .default).weight(selectedOccasion == value ? .semibold : .regular))
                .foregroundStyle(selectedOccasion == value ? Theme.accent : Theme.mutedForeground)
                .padding(.horizontal, 3)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selectedOccasion == value ? Theme.accent.opacity(0.7) : .clear)
                        .frame(height: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func recommendationScore(_ item: FeedItemDTO, preferences: Set<String>) -> Int {
        let text = [item.caption, item.occasion, item.profiles?.nickname]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let preferenceMatches = preferences.reduce(into: 0) { score, preference in
            if text.contains(preference) { score += 3 }
        }
        return preferenceMatches + min(item.fitCheckVotes.count, 20)
            + (item.createdAt > Date().addingTimeInterval(-86_400) ? 2 : 0)
            + (signalScores[item.id] ?? 0)
    }

    private static let occasionOptions = ["Everyday", "Work", "Date", "Interview", "Party", "Travel", "Wedding"]

    private var sortTitle: String {
        switch sort {
        case .forYou: "For you"
        case .newest: "Newest"
        case .votes: "Top voted"
        }
    }

    private func loadUnreadCount() async {
        // A badge failure must not hide an otherwise usable feed.
        if let count = try? await API.fetchUnreadNotificationCount(recipientId: appState.userId) {
            unreadCount = count
        }
    }

    private func load() async {
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        error = nil
        nextOffset = 0
        canLoadMore = true
        defer { if loadID == requestID { isLoading = false } }
        do {
            async let followingTask = API.fetchFollowingIDs(userId: appState.userId)
            async let friendsTask = API.fetchFriendIDs(userId: appState.userId)
            async let signalTask = API.fetchFeedSignalScores(userId: appState.userId)
            async let countTask: Void = loadUnreadCount()
            let following = try await followingTask
            let friends = (try? await friendsTask) ?? []
            let page = try await API.fetchFeedPage(offset: 0, limit: pageSize,
                                                   search: searchText, occasion: selectedOccasion,
                                                   followingIDs: mode == .following ? following : nil,
                                                   friendIDs: friends)
            guard loadID == requestID else { return }
            items = page.items
            nextOffset = page.fetchedCount
            canLoadMore = page.fetchedCount == pageSize
            followingIDs = following
            friendIDs = friends
            signalScores = (try? await signalTask) ?? signalScores
            hasLoaded = true
            await countTask
        } catch is CancellationError {
            return
        } catch {
            if loadID == requestID { self.error = "Couldn’t load this content. Please try again." }
        }
    }

    private func loadMoreIfNeeded() async {
        guard !isLoading, !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await API.fetchFeedPage(offset: nextOffset, limit: pageSize,
                                                   search: searchText, occasion: selectedOccasion,
                                                   followingIDs: mode == .following ? followingIDs : nil,
                                                   friendIDs: friendIDs)
            let existing = Set(items.map(\.id))
            let fresh = page.items.filter { !existing.contains($0.id) }
            items.append(contentsOf: fresh)
            nextOffset += page.fetchedCount
            canLoadMore = page.fetchedCount == pageSize
        } catch is CancellationError {
            return
        } catch {
            // Pagination is additive. Keep the loaded feed usable and let the
            // next appearance attempt the request again.
            canLoadMore = true
        }
    }

    private func toggleFollow(_ creatorId: UUID, follow: Bool) {
        if follow { followingIDs.insert(creatorId) } else { followingIDs.remove(creatorId) }
        Task {
            do {
                try await API.setFollowing(follow, followerId: appState.userId, followingId: creatorId)
                logEventForCreator(creatorId, event: follow ? "follow" : "unfollow")
            } catch {
                if follow { followingIDs.remove(creatorId) } else { followingIDs.insert(creatorId) }
                self.error = "Couldn’t update your following list. Please try again."
            }
        }
    }

    private func logImpression(for item: FeedItemDTO) {
        guard loggedImpressions.insert(item.id).inserted else { return }
        logEvent(item, event: "impression")
    }

    private func logEvent(_ item: FeedItemDTO, event: String) {
        Task { try? await API.logFeedEvent(userId: appState.userId, fitCheckId: item.id, event: event) }
    }

    private func logEventForCreator(_ creatorId: UUID, event: String) {
        guard let item = items.first(where: { $0.creatorId == creatorId }) else { return }
        logEvent(item, event: event)
    }
}

private struct DailyChallengeCard: View {
    @Environment(\.openURL) private var openURL
    let challenge: DailyChallenge
    let weather: LocalWeatherConditions?
    let isWeatherLoading: Bool
    let locationDenied: Bool
    let errorMessage: String?
    let onUseWeather: () -> Void
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onJoin) {
                HStack(spacing: 12) {
                    Image(systemName: challengeSymbol)
                        .font(.system(size: 20, weight: .regular, design: .default))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today's prompt")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(Theme.mutedForeground)
                        Text(challenge.title)
                            .font(Theme.editorialFont(size: 23, relativeTo: .title3))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(challenge.prompt)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                if let weather {
                    Label(weather.summary, systemImage: weather.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 4)
                    Link(destination: URL(string: "https://open-meteo.com/")!) {
                        Text("Weather · Open-Meteo")
                            .font(.system(size: 10, weight: .medium))
                    }
                } else {
                    Image(systemName: "location.circle")
                        .font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
                    Text("Dress for your local weather")
                        .font(.system(size: 11)).foregroundStyle(Theme.mutedForeground)
                    Spacer(minLength: 2)
                    Button {
                        if locationDenied, let settings = URL(string: UIApplication.openSettingsURLString) {
                            openURL(settings)
                        } else {
                            onUseWeather()
                        }
                    } label: {
                        if isWeatherLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(locationDenied ? "Open Settings" : "Use local weather")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .disabled(isWeatherLoading)
                    .foregroundStyle(Theme.accent)
                }
            }
            if weather == nil, let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
            }
            Text("Your location is sent to Open-Meteo to get current weather; CLO-V doesn't save it.")
                .font(.system(size: 9)).foregroundStyle(Theme.mutedForeground.opacity(0.85))
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line.opacity(0.1), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dailyChallengeCard")
    }

    private var challengeSymbol: String {
        switch challenge.id {
        case "weather-rain": "cloud.rain"
        case "weather-cold", "weather-snow": "snowflake"
        case "weather-hot", "weather-sunny": "sun.max"
        case "weather-wind": "wind"
        case "lecture": "graduationcap"
        case "rain": "cloud.rain"
        case "date": "sparkles"
        case "interview": "briefcase"
        default: "sun.max"
        }
    }
}

#if DEBUG
/// Local-only interactive preview for checking the live voting card on the
/// simulator. Votes stay in this view and are never written to Supabase.
private struct SampleVotingSessionCard: View {
    @State private var selectedLook: Int?
    @State private var showingDetails = false

    private let looks: [(id: Int, title: String, imageURL: String, votes: Int)] = [
        (1, "Soft layers", "https://images.unsplash.com/photo-1539109136881-3be0616acf4b?auto=format&fit=crop&w=900&q=85", 7),
        (2, "Cool classic", "https://images.unsplash.com/photo-1529139574466-a303027c1d8b?auto=format&fit=crop&w=900&q=85", 5)
    ]

    private var totalVotes: Int { looks.reduce(0) { $0 + $1.votes } + (selectedLook == nil ? 0 : 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                AvatarView(url: nil, nickname: "Maya", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maya Chen")
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Sample Fit-Check")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }
                Spacer()
                Label("LIVE", systemImage: "circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.iconSage)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.iconSage.opacity(0.11), in: Capsule())
            }

            Text("Which look works for a coffee date?")
                .font(.system(.subheadline, design: .default).weight(.semibold))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 9) {
                ForEach(looks, id: \.id) { look in
                    Button {
                        guard selectedLook == nil else { return }
                        withAnimation(Theme.press) { selectedLook = look.id }
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            ZStack(alignment: .bottomLeading) {
                                RemoteImage(url: look.imageURL)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 196)
                                    .clipped()
                                LinearGradient(colors: [.clear, .black.opacity(0.52)], startPoint: .center, endPoint: .bottom)
                                HStack {
                                    Text("LOOK \(look.id == 1 ? "A" : "B")")
                                        .font(.system(size: 10, weight: .black))
                                        .tracking(0.8)
                                    Spacer()
                                    if selectedLook == look.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 17, weight: .semibold))
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(9)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(selectedLook == look.id ? Theme.accent : Theme.line.opacity(0.10), lineWidth: selectedLook == look.id ? 2 : 1)
                            }

                            HStack(spacing: 5) {
                                Text(look.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if selectedLook != nil {
                                    Text("\(Int((Double(look.votes + (selectedLook == look.id ? 1 : 0)) / Double(totalVotes) * 100).rounded()))%")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedLook != nil)
                    .accessibilityLabel("Vote for look \(look.id == 1 ? "A" : "B"), \(look.title)")
                }
            }

            HStack {
                Label("\(totalVotes) votes", systemImage: "chart.bar.fill")
                Spacer()
                Button { showingDetails = true } label: {
                    Label("3 comments", systemImage: "bubble.left")
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .font(.system(.caption, design: .default).weight(.medium))
            .foregroundStyle(Theme.mutedForeground)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Theme.line.opacity(0.1), lineWidth: 1))
        .sheet(isPresented: $showingDetails) {
            SampleFitCheckDetailView()
        }
    }
}

private struct SampleComment: Identifiable {
    let id = UUID()
    let author: String
    let message: String
}

private struct SampleFitCheckDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var comments = [
        SampleComment(author: "Ava", message: "The soft layers feel perfect for a coffee date."),
        SampleComment(author: "Nina", message: "Look B feels polished without being too dressed up."),
        SampleComment(author: "Jules", message: "A for me — love the proportions!")
    ]

    private let imageURLs = [
        "https://images.unsplash.com/photo-1539109136881-3be0616acf4b?auto=format&fit=crop&w=900&q=85",
        "https://images.unsplash.com/photo-1529139574466-a303027c1d8b?auto=format&fit=crop&w=900&q=85"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("LIVE FIT-CHECK · SAMPLE")
                        .font(.system(.caption2, design: .default).weight(.black))
                        .tracking(1.3)
                        .foregroundStyle(Theme.accent)

                    HStack(spacing: 10) {
                        AvatarView(url: nil, nickname: "Maya", size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Maya Chen").font(.system(.subheadline, design: .default).weight(.semibold))
                            Text("4 hours left · Coffee date")
                                .font(.caption)
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        Spacer()
                    }

                    Text("Which look works for a coffee date?")
                        .font(Theme.editorialFont(size: 26, relativeTo: .title2))
                        .foregroundStyle(Theme.ink)

                    HStack(spacing: 10) {
                        ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteImage(url: url)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 250)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                Text(index == 0 ? "LOOK A · SOFT LAYERS" : "LOOK B · COOL CLASSIC")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(0.3)
                                    .foregroundStyle(Theme.mutedForeground)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    HStack {
                        Label("12 votes", systemImage: "chart.bar.fill")
                        Spacer()
                        Label("Voting is open", systemImage: "clock")
                    }
                    .font(.system(.caption, design: .default).weight(.medium))
                    .foregroundStyle(Theme.mutedForeground)

                    Rectangle().fill(Theme.line.opacity(0.12)).frame(height: 1)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Notes from the circle")
                            .font(Theme.editorialFont(size: 23, relativeTo: .title3))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(comments.count)")
                            .font(.system(.caption, design: .default).weight(.semibold))
                            .foregroundStyle(Theme.mutedForeground)
                    }

                    ForEach(comments) { comment in
                        HStack(alignment: .top, spacing: 10) {
                            AvatarView(url: nil, nickname: comment.author, size: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(comment.author)
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                Text(comment.message)
                                    .font(.system(.subheadline, design: .default))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    TextField("Add a comment…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.muted, in: Capsule())
                    Button(action: postComment) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.inverseText)
                            .frame(width: 38, height: 38)
                            .background(Theme.ink, in: Circle())
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Post comment")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.background)
            }
            .navigationTitle("Fit-Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func postComment() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        comments.append(SampleComment(author: "You", message: message))
        draft = ""
        Haptics.success()
    }
}
#endif

/// An immersive, one-look-at-a-time feed. The regular editorial feed remains
/// useful for scanning; this view provides the fast vertical loop for users
/// who want to browse and vote quickly.
private struct SwipeFeedView: View {
    let items: [FeedItemDTO]
    let voterId: UUID
    let followingIDs: Set<UUID>
    let isFollowingMode: Bool
    let onModeChange: (Bool) -> Void
    let onBrowse: () -> Void
    let onToggleFollow: (UUID, Bool) -> Void
    let onEvent: (FeedItemDTO, String) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(isFollowingMode ? "Your people are getting dressed." : "Your next favorite look is out there.")
                        .font(.system(.title3, design: .default).weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(isFollowingMode ? "Follow a few creators to fill this feed." : "Be the first to post a Fit-Check and get the conversation started.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button(action: onBrowse) {
                        Label("Explore Fit-Checks", systemImage: "safari")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            SwipeFitCheckPage(
                                item: item,
                                voterId: voterId,
                                isFollowing: followingIDs.contains(item.creatorId),
                                onToggleFollow: { onToggleFollow(item.creatorId, $0) },
                                onEvent: { onEvent(item, $0) }
                            )
                            .containerRelativeFrame(.vertical)
                        }
                    }
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
            }

            HStack(alignment: .center, spacing: 0) {
                Text("CLO·V")
                    .font(.system(size: 18, weight: .black, design: .default))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                modeButton("For You", selected: !isFollowingMode) { onModeChange(false) }
                modeButton("Following", selected: isFollowingMode) { onModeChange(true) }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 58)
            .padding(.bottom, 12)
            .background(LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
        }
        .background(.black)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: selected ? .bold : .medium))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.72))
                Capsule()
                    .fill(selected ? Theme.accent : .clear)
                    .frame(width: selected ? 28 : 8, height: 3)
            }
            .frame(minWidth: 66)
        }
        .buttonStyle(.plain)
    }
}

private struct SwipeFitCheckPage: View {
    let item: FeedItemDTO
    let voterId: UUID
    let onToggleFollow: (Bool) -> Void
    let onEvent: (String) -> Void
    @State private var isFollowing: Bool
    @State private var didLogImpression = false

    init(item: FeedItemDTO, voterId: UUID, isFollowing: Bool, onToggleFollow: @escaping (Bool) -> Void, onEvent: @escaping (String) -> Void) {
        self.item = item
        self.voterId = voterId
        self.onToggleFollow = onToggleFollow
        self.onEvent = onEvent
        _isFollowing = State(initialValue: isFollowing)
    }

    private var photo: FitCheckPhoto? { item.fitCheckPhotos.sorted { $0.position < $1.position }.first }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                if let photo {
                    RemoteImage(url: photo.imageUrl)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Theme.muted
                }
                Theme.photoScrim

                HStack(alignment: .bottom, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 9) {
                            Text("@\(item.profiles?.nickname ?? "closetfriend")")
                                .font(.system(.subheadline, design: .default).weight(.bold))
                            if item.creatorId != voterId {
                                Button(isFollowing ? "Following" : "+ Follow") {
                                    isFollowing.toggle()
                                    onToggleFollow(isFollowing)
                                }
                                .font(.system(.caption, design: .default).weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isFollowing ? .white.opacity(0.18) : Theme.accent, in: Capsule())
                            }
                        }

                        if let caption = item.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.system(.subheadline, design: .default).weight(.medium))
                                .lineLimit(3)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "music.note")
                            Text("CLO·V STYLE CHECK  ·  \((item.occasion ?? "STYLE").uppercased())")
                                .lineLimit(1)
                        }
                        .font(.system(size: 10, weight: .bold, design: .default))
                        .foregroundStyle(.white.opacity(0.88))

                        NavigationLink {
                            FitCheckDetailView(fitCheckId: item.id)
                        } label: {
                            Label("Vote on the looks", systemImage: "sparkles")
                                .font(.system(.caption, design: .default).weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(.white.opacity(0.18), in: Capsule())
                        }
                        .simultaneousGesture(TapGesture().onEnded { onEvent("open_detail") })
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 18) {
                        AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname, size: 46, ringed: true)
                            .overlay(alignment: .bottom) {
                                if item.creatorId != voterId {
                                    Image(systemName: isFollowing ? "checkmark" : "plus")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(.white)
                                        .frame(width: 20, height: 20)
                                        .background(Theme.accent, in: Circle())
                                        .offset(y: 8)
                                }
                            }
                            .onTapGesture {
                                guard item.creatorId != voterId else { return }
                                isFollowing.toggle()
                                onToggleFollow(isFollowing)
                            }
                        NavigationLink {
                            FitCheckDetailView(fitCheckId: item.id)
                        } label: {
                            feedAction("heart.fill", count: item.fitCheckVotes.count, label: "Vote")
                        }
                        .simultaneousGesture(TapGesture().onEnded { onEvent("open_detail") })
                        NavigationLink {
                            FitCheckDetailView(fitCheckId: item.id)
                        } label: {
                            feedAction("bubble.right.fill", count: item.fitCheckComments.count, label: "Comments")
                        }
                        ShareLink(item: "Check out this Fit-Check on CLO·V") {
                            feedAction("paperplane.fill", count: nil, label: "Share")
                        }
                        .simultaneousGesture(TapGesture().onEnded { onEvent("share") })
                    }
                    .frame(width: 50)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.bottom, 112)
            }
            .contentShape(Rectangle())
            .onAppear {
                guard !didLogImpression else { return }
                didLogImpression = true
                onEvent("impression")
            }
        }
    }

    private func feedAction(_ symbol: String, count: Int?, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .semibold))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .default))
            }
        }
        .frame(width: 48, height: 46)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { "\(label), \($0)" } ?? label)
    }
}

private struct SwipeActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .default).weight(.bold))
            .foregroundStyle(Theme.inverseText)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.black.opacity(configuration.isPressed ? 0.8 : 0.58), in: Capsule())
    }
}
