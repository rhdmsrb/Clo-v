import Foundation

/// Rules for which wardrobe pieces can be worn together in the outfit planner.
enum OutfitSelection {
    private static let onePieceCategories: Set<String> = ["dress", "set"]
    private static let upperBodyCategories: Set<String> = ["top", "outerwear"]

    /// Categories that a newly chosen piece of `category` takes the place of.
    static func conflictingCategories(for category: String) -> Set<String> {
        if onePieceCategories.contains(category) { return ["dress", "set", "top", "bottom", "outerwear"] }
        if upperBodyCategories.contains(category) { return ["dress", "set", "top", "outerwear"] }
        if category == "bottom" { return ["dress", "set", "bottom"] }
        return [category]
    }

    /// The selection after tapping `item`: deselects it if selected, otherwise
    /// selects it and drops any selected pieces it can't be worn with.
    static func toggling(_ item: WardrobeItem, selected: Set<UUID>, in wardrobe: [WardrobeItem]) -> Set<UUID> {
        if selected.contains(item.id) { return selected.subtracting([item.id]) }
        let conflicts = conflictingCategories(for: item.category)
        let replacedIDs = wardrobe.filter { conflicts.contains($0.category) }.map(\.id)
        return selected.subtracting(replacedIDs).union([item.id])
    }
}

extension OutfitSelection {
    /// Splits a saved look's piece IDs into those still in the wardrobe and a
    /// count of pieces that have since been deleted.
    static func resolve(_ itemIDs: [UUID], in wardrobe: [WardrobeItem]) -> (present: Set<UUID>, missingCount: Int) {
        let available = Set(wardrobe.map(\.id))
        let present = Set(itemIDs).intersection(available)
        return (present, Set(itemIDs).count - present.count)
    }
}
