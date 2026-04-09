public typealias SafeWriteOptions = WriteOptions

public struct WriteOptions: Sendable {
    // /// If true and the file exists & is not blank, allow overwrite.
    // public var overrideExisting: Bool
    public var existingFilePolicy: ExistingFilePolicy

    /// If overriding, also write a backup first.
    public var makeBackupOnOverride: Bool
    /// Treat whitespace-only files as "blank".
    public var whitespaceOnlyIsBlank: Bool
    /// When making a backup, append this suffix to the filename.
    /// Example: "notes.txt" -> "notes.txt_previous_version.bak"
    public var backupSuffix: String
    /// If a backup with the same name already exists, add a timestamp to avoid clobbering.
    public var addTimestampIfBackupExists: Bool
    public var createIntermediateDirectories: Bool
    /// Write atomically (via `.atomic`).
    public var atomic: Bool

    /// If true, store backups in <target-dir>/safe-file-backups/overwrite_<timestamp>/.
    public var createBackupDirectory: Bool
    /// Name of the folder created in the target file's directory.
    public var backupDirectoryName: String
    /// Prefix used for subfolders representing one overwrite operation.
    public var backupSetPrefix: String
    /// Keep at most this many backup SET folders (per target directory). Nil = unlimited.
    public var maxBackupSets: Int?

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
        maxBackupSets: Int? = nil
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
    }

    @available(*, deprecated, renamed: "existingFilePolicy")
    public var overrideExisting: Bool {
        get { existingFilePolicy == .overwrite }
        set { existingFilePolicy = newValue ? .overwrite : .abort }
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
        maxBackupSets: Int? = nil
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
            maxBackupSets: maxBackupSets
        )
    }

    public static let overwrite: Self = .init(
        // overrideExisting: true,
        existingFilePolicy: .overwrite,
        whitespaceOnlyIsBlank: true,
        maxBackupSets: 10
    )
}
