import Foundation

#if DEBUG
extension SampleData {
    /// One canned Fit-Check. `expiresInHours` is relative to launch time and
    /// negative once expired; `nil` never expires.
    struct Fixture {
        let number: Int
        let creator: Person
        let caption: String
        let occasion: String?
        let votePrompt: String?
        let votesPerPhoto: [Int]
        let commentCount: Int
        let postedHoursAgo: Double
        let expiresInHours: Double?
        var status = "live"
        var groupNumber: Int?

        var id: UUID { SampleData.uuid(1_000 + number) }
        var isPublic: Bool { groupNumber == nil }
        var expiresAt: Date? { expiresInHours.map { Date().addingTimeInterval(SampleData.hours($0)) } }
        var createdAt: Date { Date().addingTimeInterval(-SampleData.hours(postedHoursAgo)) }
        var groupId: UUID? { groupNumber.map { SampleData.uuid(3_000 + $0) } }

        var photos: [FitCheckPhoto] {
            votesPerPhoto.indices.map { index in
                FitCheckPhoto(id: SampleData.uuid(10_000 + number * 10 + index), fitCheckId: id,
                              imageUrl: SampleData.imageURL(kind: "photo", number: number * 10 + index),
                              position: index + 1)
            }
        }

        var votes: [VoteRef] {
            photos.enumerated().flatMap { index, photo in
                (0..<votesPerPhoto[index]).map { voter in
                    VoteRef(photoId: photo.id, voterId: SampleData.uuid(900 + voter))
                }
            }
        }

        var feedItem: FeedItemDTO {
            FeedItemDTO(id: id, creatorId: creator.id, caption: caption, occasion: occasion,
                        audience: isPublic ? "public" : "group", votePrompt: votePrompt,
                        createdAt: createdAt, expiresAt: expiresAt, fitCheckPhotos: photos,
                        fitCheckVotes: votes,
                        fitCheckComments: (0..<commentCount).map { CommentRef(id: SampleData.uuid(5_000 + number * 10 + $0)) },
                        profiles: creator.info)
        }

        var detail: FitCheckDetailDTO {
            FitCheckDetailDTO(id: id, caption: caption, occasion: occasion,
                              audience: isPublic ? "public" : "group", votePrompt: votePrompt,
                              status: status, creatorId: creator.id, expiresAt: expiresAt,
                              fitCheckPhotos: photos, profiles: creator.info)
        }
    }

    static let fixtures: [Fixture] = [
        Fixture(number: 1, creator: maya, caption: "Soft layers for the gallery opening",
                occasion: "Date night", votePrompt: "Which one feels more effortless?",
                votesPerPhoto: [5, 3], commentCount: 3, postedHoursAgo: 2, expiresInHours: 20),
        Fixture(number: 2, creator: jun, caption: "Work fit: blazer or bomber?",
                occasion: "Work", votePrompt: nil,
                votesPerPhoto: [4, 6, 2], commentCount: 1, postedHoursAgo: 5, expiresInHours: 6),
        Fixture(number: 3, creator: sora, caption: "Brunch outfit, which one?",
                occasion: "Brunch", votePrompt: nil,
                votesPerPhoto: [9, 11], commentCount: 4, postedHoursAgo: 30, expiresInHours: -3),
        Fixture(number: 4, creator: alex,
                caption: "Trying a much longer caption here to see how the card copes when someone writes a full paragraph about a thrifted jacket, wide trousers and the shoes they almost did not buy.",
                occasion: nil, votePrompt: nil,
                votesPerPhoto: [0, 0], commentCount: 0, postedHoursAgo: 8, expiresInHours: nil),
        Fixture(number: 5, creator: me, caption: "My rainy day commute look",
                occasion: "Casual", votePrompt: nil,
                votesPerPhoto: [2, 1], commentCount: 2, postedHoursAgo: 1, expiresInHours: 10),
        Fixture(number: 6, creator: me, caption: "Last weekend's thrift haul",
                occasion: "Casual", votePrompt: nil,
                votesPerPhoto: [6, 2], commentCount: 0, postedHoursAgo: 72, expiresInHours: nil,
                status: "archived"),
        Fixture(number: 7, creator: me, caption: "Concert night",
                occasion: "Party", votePrompt: nil,
                votesPerPhoto: [3, 3], commentCount: 1, postedHoursAgo: 26, expiresInHours: -1),
        Fixture(number: 8, creator: maya, caption: "Sunday market uniform",
                occasion: "Casual", votePrompt: nil,
                votesPerPhoto: [2, 4], commentCount: 2, postedHoursAgo: 4, expiresInHours: 12,
                groupNumber: 1),
        Fixture(number: 9, creator: jun, caption: "Board meeting, be honest",
                occasion: "Work", votePrompt: nil,
                votesPerPhoto: [1, 0], commentCount: 0, postedHoursAgo: 6, expiresInHours: 18,
                groupNumber: 1)
    ]

    static func fixture(id: UUID) -> Fixture? { fixtures.first { $0.id == id } }

    static var publicFeed: [FeedItemDTO] {
        fixtures
            .filter { $0.isPublic && $0.status == "live" && ($0.creator.id != me.id || $0.number == 5) }
            .map(\.feedItem)
    }

    static func feedPage(offset: Int, limit: Int, search: String, occasion: String?,
                         followingIDs: Set<UUID>?) -> API.FeedPageResult {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = publicFeed.filter { item in
            (followingIDs.map { $0.contains(item.creatorId) } ?? true)
                && (occasion.map { item.occasion == $0 } ?? true)
                && (term.isEmpty || (item.caption ?? "").lowercased().contains(term))
        }
        let page = Array(matching.dropFirst(offset).prefix(max(0, limit)))
        return API.FeedPageResult(items: page, fetchedCount: page.count)
    }

    static func groupFeed(groupId: UUID) -> [FeedItemDTO] {
        fixtures.filter { $0.groupId == groupId }.map(\.feedItem)
    }

    static func myFitChecks() -> [MyFitCheck] {
        fixtures.filter { $0.creator.id == me.id }.map { fixture in
            MyFitCheck(id: fixture.id, caption: fixture.caption, status: fixture.status,
                       expiresAt: fixture.expiresAt, thumbnailURL: fixture.photos.first?.imageUrl)
        }
    }

    static func votes(fitCheckId: UUID) -> [VoteRef] { fixture(id: fitCheckId)?.votes ?? [] }

    static func comments(fitCheckId: UUID) -> [CommentDTO] {
        guard let fixture = fixture(id: fitCheckId) else { return [] }
        let bodies = [
            "Left one, the proportions are perfect.",
            "Love the color story. Where are the shoes from?",
            "Right one for sure, but swap the belt.",
            "Honestly both work, depends on the weather."
        ]
        return (0..<fixture.commentCount).map { index in
            let author = others[index % others.count]
            return CommentDTO(id: uuid(5_000 + fixture.number * 10 + index), body: bodies[index % bodies.count],
                              createdAt: Date().addingTimeInterval(-hours(Double(index + 1))),
                              profiles: author.info)
        }
    }
}
#endif
