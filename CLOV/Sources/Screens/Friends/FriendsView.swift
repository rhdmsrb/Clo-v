import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var searchResults: [AuthorInfoWithId] = []
    @State private var incoming: [FriendRequestDTO] = []
    @State private var outgoing: [FriendRequestDTO] = []
    @State private var friends: [AuthorInfoWithId] = []
    @State private var peopleById: [UUID: AuthorInfoWithId] = [:]
    @State private var isLoading = true
    @State private var error: String?
    @State private var hasSearched = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Friends").font(Theme.editorialFont(size: 38))
                Text("Build the circle that helps you choose your best fit.")
                    .foregroundStyle(Theme.mutedForeground)
                HStack {
                    TextField("Nickname, account code, email, or phone", text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    Button("Search") { Task { await search() } }
                        .font(.system(.subheadline, design: .default).weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: Theme.minTapSize)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card).clipShape(Capsule())

                if hasSearched || !searchResults.isEmpty { peopleSection("SEARCH RESULTS", people: searchResults, showAdd: true) }
                requestsSection
                peopleSection("MY FRIENDS", people: friends, showAdd: false)
                if !outgoing.isEmpty {
                    Text("SENT REQUESTS").font(.system(.caption2).weight(.bold)).foregroundStyle(.secondary)
                    ForEach(outgoing) { request in
                        personRow(peopleById[request.addresseeId], action: AnyView(Button("Cancel") { Task { await cancel(request.id) } }.accessibilityLabel("Cancel request to \(name(request.addresseeId))")))
                    }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
            }
            .padding(20)
        }
        .background(Theme.background)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private var requestsSection: some View {
        Text("INCOMING REQUESTS").font(.system(.caption2).weight(.bold)).foregroundStyle(.secondary)
        if incoming.isEmpty { Text("No pending requests.").font(.subheadline).foregroundStyle(Theme.mutedForeground) }
        else { ForEach(incoming) { request in personRow(peopleById[request.requesterId], action: AnyView(HStack(spacing: 8) { Button("Accept") { Task { await respond(request.id, accept: true) } }.foregroundStyle(Theme.accent).accessibilityLabel("Accept request from \(name(request.requesterId))"); Button("Decline") { Task { await respond(request.id, accept: false) } }.foregroundStyle(.secondary).accessibilityLabel("Decline request from \(name(request.requesterId))") })) } }
    }

    @ViewBuilder private func peopleSection(_ title: String, people: [AuthorInfoWithId], showAdd: Bool) -> some View {
        Text(title).font(.system(.caption2).weight(.bold)).foregroundStyle(.secondary)
        if people.isEmpty { Text(showAdd ? "No users found." : "Add friends and family to start your circle.").font(.subheadline).foregroundStyle(Theme.mutedForeground) }
        else { ForEach(people) { person in personRow(person, action: showAdd ? AnyView(Button("Add") { Task { await send(person.id) } }.foregroundStyle(Theme.accent).accessibilityLabel("Add \(person.nickname) as a friend")) : nil) } }
    }

    private func name(_ id: UUID) -> String { peopleById[id]?.nickname ?? "this person" }

    private func personRow(_ person: AuthorInfoWithId?, action: AnyView?) -> some View {
        HStack(spacing: 12) {
            AvatarView(url: person?.avatarUrl, nickname: person?.nickname, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(person?.nickname ?? "Someone").font(.system(.subheadline, design: .default).weight(.semibold))
                if let person {
                    Text(person.accountCode + (person.mutualCount > 0 ? " · \(person.mutualCount) mutual" : ""))
                        .font(.caption2).foregroundStyle(Theme.mutedForeground)
                }
            }
            Spacer(); action.frame(minHeight: Theme.minTapSize)
        }.softCard(radius: 18, padding: 12)
    }

    private func load() async {
        isLoading = true; error = nil
        do {
            async let inc = API.fetchFriendRequests(userId: appState.userId, incoming: true)
            async let out = API.fetchFriendRequests(userId: appState.userId, incoming: false)
            async let fs = API.fetchFriendships(userId: appState.userId)
            incoming = try await inc; outgoing = try await out
            let rows = try await fs
            let ids = rows.map { $0.userLow == appState.userId ? $0.userHigh : $0.userLow }
            friends = try await API.fetchProfiles(ids: ids)
            let requestIds = incoming.map(\.requesterId) + outgoing.map(\.addresseeId)
            peopleById = Dictionary(uniqueKeysWithValues: try await API.fetchProfiles(ids: Array(Set(requestIds + ids))).map { ($0.id, $0) })
        } catch let e { error = e.localizedDescription }
        isLoading = false
    }

    private func search() async {
        error = nil
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
            searchResults = []
            hasSearched = false
            error = "Type at least 2 characters to search."
            return
        }
        do {
            let people = try await API.searchProfiles(query: query, excluding: appState.userId)
            let counts = try await API.fetchMutualFriendCounts(userIds: people.map(\.id))
            let byId = Dictionary(uniqueKeysWithValues: counts.map { ($0.userId, $0.mutualCount) })
            searchResults = people.map { var person = $0; person.mutualCount = byId[person.id] ?? 0; return person }
            hasSearched = true
        } catch let e { error = e.localizedDescription }
    }
    private func send(_ id: UUID) async { do { try await API.sendFriendRequest(to: id); await load() } catch let e { error = e.localizedDescription } }
    private func respond(_ id: UUID, accept: Bool) async { do { try await API.respondFriendRequest(id: id, accept: accept); await load() } catch let e { error = e.localizedDescription } }
    private func cancel(_ id: UUID) async { do { try await API.cancelFriendRequest(id: id); await load() } catch let e { error = e.localizedDescription } }
}
