import Foundation

#if DEBUG
extension SampleData {
    // MARK: - Notifications

    static var notifications: [NotificationDTO] {
        func make(_ number: Int, _ type: String, read: Bool, hoursAgo: Double,
                  actor: Person, fitCheck: Int?) -> NotificationDTO {
            NotificationDTO(id: uuid(4_000 + number), type: type, isRead: read,
                            createdAt: Date().addingTimeInterval(-hours(hoursAgo)),
                            fitCheckId: fitCheck.map { uuid(1_000 + $0) }, actor: actor.info)
        }
        return [
            make(1, "vote", read: false, hoursAgo: 0.1, actor: maya, fitCheck: 5),
            make(2, "friend_request", read: false, hoursAgo: 1, actor: jun, fitCheck: nil),
            make(3, "comment", read: true, hoursAgo: 3, actor: sora, fitCheck: 5),
            make(4, "vote", read: true, hoursAgo: 26, actor: alex, fitCheck: 7),
            make(5, "friend_accepted", read: true, hoursAgo: 50, actor: sora, fitCheck: nil)
        ]
    }

    static var unreadNotificationCount: Int { notifications.filter { !$0.isRead }.count }

    // MARK: - Groups

    static let groups: [FashionGroup] = [
        FashionGroup(id: uuid(3_001), name: "Sunday Stylists", creatorId: me.id, inviteCode: "SUNDAY",
                     createdAt: Date().addingTimeInterval(-hours(24 * 20))),
        FashionGroup(id: uuid(3_002), name: "Office Fits", creatorId: maya.id, inviteCode: "OFFICE",
                     createdAt: Date().addingTimeInterval(-hours(24 * 9)))
    ]

    static func group(id: UUID) -> FashionGroup? { groups.first { $0.id == id } }

    static func members(groupId: UUID) -> [GroupMemberDisplay] {
        let people: [Person] = groupId == groups[0].id ? [me, maya, jun, sora] : [me, maya, alex, riley]
        return people.map { GroupMemberDisplay(id: $0.id, nickname: $0.nickname, avatarUrl: $0.avatarUrl) }
    }

    // MARK: - Wardrobe

    static var wardrobeItems: [WardrobeItem] {
        let rows: [(String, String, String, String, String)] = [
            ("Oversized denim jacket", "outerwear", "Blue", "fall", "Levi's"),
            ("White tee", "top", "White", "all", "Uniqlo"),
            ("Wide-leg trousers", "bottom", "Charcoal", "all", "COS"),
            ("Leather sneakers", "shoes", "White", "spring", "Common Projects"),
            ("Slip dress", "dress", "Sage", "summer", "Reformation"),
            ("Wool scarf", "accessory", "Camel", "winter", "Acne Studios")
        ]
        return rows.enumerated().map { index, row in
            WardrobeItem(id: uuid(6_000 + index), ownerId: me.id,
                         imageUrl: imageURL(kind: "item", number: index), name: row.0, category: row.1,
                         subcategory: nil, color: row.2, season: row.3, brand: row.4,
                         wearFrequency: index.isMultiple(of: 2) ? "often" : "sometimes",
                         tags: index == 0 ? ["vintage", "layering"] : [],
                         createdAt: Date().addingTimeInterval(-hours(Double(index + 1) * 24)), updatedAt: nil)
        }
    }

    // MARK: - Writes

    static func createdGroup(name: String) -> FashionGroup {
        FashionGroup(id: uuid(3_099), name: name, creatorId: me.id, inviteCode: "NEWGRP", createdAt: Date())
    }
}
#endif
