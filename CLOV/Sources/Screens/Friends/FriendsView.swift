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
                header
                searchField
                if hasSearched || !searchResults.isEmpty { peopleSection("Search results", people: searchResults, showAdd: true) }
                requestsSection
                peopleSection("My friends", people: friends, showAdd: false)
                sentSection
                if let error { Text(error).font(Theme.label).foregroundStyle(Theme.danger) }
            }
            .padding(20)
        }
        .background(Theme.background)
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Friends")
                .font(Theme.editorialFont(size: 38, relativeTo: .largeTitle))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityAddTraits(.isHeader)
            Text("Build the circle that helps you choose your best fit.")
                .font(Theme.body)
                .foregroundStyle(Theme.mutedForeground)
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Find people")
                .font(Theme.label)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityHidden(true)
                TextField("Nickname, account code, email, or phone", text: $query)
                    .font(Theme.body)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel("Find people")
                    .onSubmit { Task { await search() } }
                Button("Search") { Task { await search() } }
                    .font(Theme.label)
                    .foregroundStyle(Theme.accentDeep)
                    .frame(minHeight: Theme.minTapSize)
            }
            .padding(.horizontal, 16)
            .background(Theme.muted, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
        }
    }

    @ViewBuilder private var requestsSection: some View {
        SectionHeader(title: "Incoming requests")
        if incoming.isEmpty {
            Text("No pending requests.").font(Theme.body).foregroundStyle(Theme.mutedForeground)
        } else {
            ForEach(incoming) { request in
                personRow(peopleById[request.requesterId], action: AnyView(incomingActions(request)))
            }
        }
    }

    private func incomingActions(_ request: FriendRequestDTO) -> some View {
        HStack(spacing: 8) {
            FriendCapsuleButton(title: "Accept", icon: "checkmark", isFilled: true) {
                Task { await respond(request.id, accept: true) }
            }
            .accessibilityLabel("Accept request from \(name(request.requesterId))")
            FriendCapsuleButton(title: "Decline", icon: nil, isFilled: false) {
                Task { await respond(request.id, accept: false) }
            }
            .accessibilityLabel("Decline request from \(name(request.requesterId))")
        }
    }

    @ViewBuilder private var sentSection: some View {
        if !outgoing.isEmpty {
            SectionHeader(title: "Sent requests")
            ForEach(outgoing) { request in
                personRow(peopleById[request.addresseeId], action: AnyView(
                    FriendCapsuleButton(title: "Cancel", icon: nil, isFilled: false) { Task { await cancel(request.id) } }
                        .accessibilityLabel("Cancel request to \(name(request.addresseeId))")
                ))
            }
        }
    }

    @ViewBuilder private func peopleSection(_ title: String, people: [AuthorInfoWithId], showAdd: Bool) -> some View {
        SectionHeader(title: title)
        if people.isEmpty {
            Text(showAdd ? "No users found." : "Add friends and family to start your circle.")
                .font(Theme.body).foregroundStyle(Theme.mutedForeground)
        } else {
            ForEach(people) { person in
                personRow(person, action: showAdd ? AnyView(addAction(person)) : nil)
            }
        }
    }

    private func addAction(_ person: AuthorInfoWithId) -> some View {
        let isRequested = outgoing.contains { $0.addresseeId == person.id }
        let isFriend = friends.contains { $0.id == person.id }
        return Group {
            if isFriend {
                FriendCapsuleButton(title: "Friends", icon: "checkmark", isFilled: true) {}
                    .disabled(true)
            } else if isRequested {
                FriendCapsuleButton(title: "Requested", icon: "clock", isFilled: true) {}
                    .disabled(true)
            } else {
                FriendCapsuleButton(title: "Add", icon: "plus", isFilled: false) { Task { await send(person.id) } }
                    .accessibilityLabel("Add \(person.nickname ?? "this person") as a friend")
            }
        }
    }

    private func name(_ id: UUID) -> String { peopleById[id]?.nickname ?? "this person" }

    private func personRow(_ person: AuthorInfoWithId?, action: AnyView?) -> some View {
        HStack(spacing: 12) {
            AvatarView(url: person?.avatarUrl, nickname: person?.nickname, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(person?.nickname ?? "Someone").font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
                if let person {
                    Text(person.accountCode + (person.mutualCount > 0 ? " · \(person.mutualCount) mutual" : ""))
                        .font(Theme.micro).foregroundStyle(Theme.mutedForeground)
                }
            }
            Spacer(minLength: 8)
            action
        }
        .softCard(radius: Theme.cardRadius, padding: 12)
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

/// Follow-style capsule: filled = accentTint with a deep-pink stroke (state shown by icon + label),
/// outline = opaque card with a control border. Always >= 44pt tall.
private struct FriendCapsuleButton: View {
    let title: String
    let icon: String?
    let isFilled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(Theme.caption).accessibilityHidden(true) }
                Text(title)
            }
            .font(Theme.label)
            .foregroundStyle(isFilled ? Theme.accentDeep : Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.minTapSize)
            .background(isFilled ? Theme.accentTint : Theme.cardElevated, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous)
                .stroke(isFilled ? Theme.accentDeep : Theme.controlBorder, lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
