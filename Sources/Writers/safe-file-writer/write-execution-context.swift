public struct WriteExecutionContext: Sendable {
    public var backupStore: (any WriteBackupStore)?

    public init(
        backupStore: (any WriteBackupStore)? = nil
    ) {
        self.backupStore = backupStore
    }
}
