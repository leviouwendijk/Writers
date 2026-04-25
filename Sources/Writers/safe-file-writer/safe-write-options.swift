public typealias SafeWriteOptions = WriteOptions

public struct WriteOptions: Sendable {
    public var existingFilePolicy: ExistingFilePolicy

    public var makeBackupOnOverride: Bool
    public var whitespaceOnlyIsBlank: Bool
    public var backupSuffix: String
    public var addTimestampIfBackupExists: Bool
    public var createIntermediateDirectories: Bool
    public var atomic: Bool

    public var createBackupDirectory: Bool
    public var backupDirectoryName: String
    public var backupSetPrefix: String
    public var maxBackupSets: Int?

    public var backupPolicy: WriteBackupPolicy
    public var backupStore: (any WriteBackupStore)?

    public var stalePlanPolicy: WriteExecutionStalePlanPolicy

    public init(
        existingFilePolicy: ExistingFilePolicy = .abort,
        makeBackupOnOverride: Bool = true,
        whitespaceOnlyIsBlank: Bool = false,
        backupSuffix: String = "_previous_version.bak",
        addTimestampIfBackupExists: Bool = true,
        createIntermediateDirectories: Bool = true,
        atomic: Bool = true,
        createBackupDirectory: Bool = true,
        backupDirectoryName: String = "safe-file-backups",
        backupSetPrefix: String = "overwrite_",
        maxBackupSets: Int? = nil,
        backupPolicy: WriteBackupPolicy = .automatic,
        backupStore: (any WriteBackupStore)? = nil,
        stalePlanPolicy: WriteExecutionStalePlanPolicy = .require_current_matches_plan
    ) {
        self.existingFilePolicy = existingFilePolicy
        self.makeBackupOnOverride = makeBackupOnOverride
        self.whitespaceOnlyIsBlank = whitespaceOnlyIsBlank
        self.backupSuffix = backupSuffix
        self.addTimestampIfBackupExists = addTimestampIfBackupExists
        self.createIntermediateDirectories = createIntermediateDirectories
        self.atomic = atomic
        self.createBackupDirectory = createBackupDirectory
        self.backupDirectoryName = backupDirectoryName
        self.backupSetPrefix = backupSetPrefix
        self.maxBackupSets = maxBackupSets
        self.backupPolicy = backupPolicy
        self.backupStore = backupStore
        self.stalePlanPolicy = stalePlanPolicy
    }

    @available(*, deprecated, renamed: "existingFilePolicy")
    public var overrideExisting: Bool {
        get {
            existingFilePolicy == .overwrite
        }
        set {
            existingFilePolicy = newValue ? .overwrite : .abort
        }
    }

    @available(*, deprecated, message: "Use init(existingFilePolicy:...) instead.")
    public init(
        overrideExisting: Bool,
        makeBackupOnOverride: Bool = true,
        whitespaceOnlyIsBlank: Bool = false,
        backupSuffix: String = "_previous_version.bak",
        addTimestampIfBackupExists: Bool = true,
        createIntermediateDirectories: Bool = true,
        atomic: Bool = true,
        createBackupDirectory: Bool = true,
        backupDirectoryName: String = "safe-file-backups",
        backupSetPrefix: String = "overwrite_",
        maxBackupSets: Int? = nil,
        backupPolicy: WriteBackupPolicy = .automatic,
        backupStore: (any WriteBackupStore)? = nil,
        stalePlanPolicy: WriteExecutionStalePlanPolicy = .require_current_matches_plan
    ) {
        self.init(
            existingFilePolicy: overrideExisting ? .overwrite : .abort,
            makeBackupOnOverride: makeBackupOnOverride,
            whitespaceOnlyIsBlank: whitespaceOnlyIsBlank,
            backupSuffix: backupSuffix,
            addTimestampIfBackupExists: addTimestampIfBackupExists,
            createIntermediateDirectories: createIntermediateDirectories,
            atomic: atomic,
            createBackupDirectory: createBackupDirectory,
            backupDirectoryName: backupDirectoryName,
            backupSetPrefix: backupSetPrefix,
            maxBackupSets: maxBackupSets,
            backupPolicy: backupPolicy,
            backupStore: backupStore,
            stalePlanPolicy: stalePlanPolicy
        )
    }

    public static let overwrite: Self = .init(
        existingFilePolicy: .overwrite,
        whitespaceOnlyIsBlank: true,
        maxBackupSets: 10
    )
}

public extension WriteOptions {
    var resolvedBackupPolicy: WriteBackupPolicy {
        guard makeBackupOnOverride else {
            return .disabled
        }

        switch backupPolicy {
        case .automatic:
            return createBackupDirectory ? .backup_directory : .sibling_file

        case .disabled,
             .sibling_file,
             .backup_directory,
             .external_store:
            return backupPolicy
        }
    }

    static let overwriteWithoutBackup: Self = .init(
        existingFilePolicy: .overwrite,
        makeBackupOnOverride: false,
        whitespaceOnlyIsBlank: true,
        backupPolicy: .disabled
    )

    static func overwriting(
        backupPolicy: WriteBackupPolicy,
        backupStore: (any WriteBackupStore)? = nil,
        maxBackupSets: Int? = 10
    ) -> Self {
        .init(
            existingFilePolicy: .overwrite,
            makeBackupOnOverride: backupPolicy != .disabled,
            whitespaceOnlyIsBlank: true,
            maxBackupSets: maxBackupSets,
            backupPolicy: backupPolicy,
            backupStore: backupStore
        )
    }
}
