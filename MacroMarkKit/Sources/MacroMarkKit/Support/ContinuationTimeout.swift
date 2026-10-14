public actor ContinuationTimeout {
    private var hasCompleted = false

    public init() {}

    public func complete() -> Bool {
        if hasCompleted { return false }
        hasCompleted = true
        return true
    }
}
