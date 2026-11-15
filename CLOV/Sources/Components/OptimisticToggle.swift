/// Pure optimistic toggle state: flip immediately, roll back on failure.
struct OptimisticToggle: Equatable {
    private(set) var isOn: Bool
    private(set) var count: Int?
    private(set) var isPending = false

    init(isOn: Bool, count: Int? = nil) {
        self.isOn = isOn
        self.count = count
    }

    /// New state to show right away; nil while a request is in flight.
    func toggled() -> OptimisticToggle? {
        guard !isPending else { return nil }
        var next = self
        next.isOn.toggle()
        next.count = count.map { max($0 + (next.isOn ? 1 : -1), 0) }
        next.isPending = true
        return next
    }

    func succeeded() -> OptimisticToggle {
        var next = self
        next.isPending = false
        return next
    }

    /// Request failed: undo the flip.
    func rolledBack() -> OptimisticToggle {
        var next = self
        next.isOn.toggle()
        next.count = count.map { max($0 + (next.isOn ? 1 : -1), 0) }
        next.isPending = false
        return next
    }

    /// Server truth arrived; ignored mid-flight so it can't undo the optimistic flip.
    func synced(isOn serverOn: Bool, count serverCount: Int?) -> OptimisticToggle {
        guard !isPending else { return self }
        return OptimisticToggle(isOn: serverOn, count: serverCount)
    }
}
