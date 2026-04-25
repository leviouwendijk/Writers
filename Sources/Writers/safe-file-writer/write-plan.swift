import Foundation

public struct WriteIncomingContent: Sendable, Codable, Hashable {
    public let data: Data
    public let text: String?

    public init(
        data: Data,
        text: String? = nil
    ) {
        self.data = data
        self.text = text
    }
}

public struct WritePlanOptions: Sendable, Codable, Hashable {
    public let existingFilePolicy: ExistingFilePolicy
    public let makeBackupOnOverride: Bool
    public let whitespaceOnlyIsBlank: Bool
    public let backupSuffix: String
    public let addTimestampIfBackupExists: Bool
    public let createIntermediateDirectories: Bool
    public let atomic: Bool
    public let createBackupDirectory: Bool
    public let backupDirectoryName: String
    public let backupSetPrefix: String
    public let maxBackupSets: Int?
    public let backupPolicy: WriteBackupPolicy
    public let resolvedBackupPolicy: WriteBackupPolicy
    public let hasBackupStore: Bool
    public let stalePlanPolicy: WriteExecutionStalePlanPolicy

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
        resolvedBackupPolicy: WriteBackupPolicy = .automatic,
        hasBackupStore: Bool = false,
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
        self.resolvedBackupPolicy = resolvedBackupPolicy
        self.hasBackupStore = hasBackupStore
        self.stalePlanPolicy = stalePlanPolicy
    }

    public init(
        _ options: SafeWriteOptions
    ) {
        self.init(
            existingFilePolicy: options.existingFilePolicy,
            makeBackupOnOverride: options.makeBackupOnOverride,
            whitespaceOnlyIsBlank: options.whitespaceOnlyIsBlank,
            backupSuffix: options.backupSuffix,
            addTimestampIfBackupExists: options.addTimestampIfBackupExists,
            createIntermediateDirectories: options.createIntermediateDirectories,
            atomic: options.atomic,
            createBackupDirectory: options.createBackupDirectory,
            backupDirectoryName: options.backupDirectoryName,
            backupSetPrefix: options.backupSetPrefix,
            maxBackupSets: options.maxBackupSets,
            backupPolicy: options.backupPolicy,
            resolvedBackupPolicy: options.resolvedBackupPolicy,
            hasBackupStore: options.backupStore != nil,
            stalePlanPolicy: options.stalePlanPolicy
        )
    }
}

public struct WritePlan: Sendable, Codable, Hashable {
    public let target: URL
    public let incoming: WriteIncomingContent
    public let options: WritePlanOptions
    public let existingData: Data?
    public let existingIsBlank: Bool
    public let overwriteAction: WriteOverwriteAction
    public let before: WriteMutationSnapshot?
    public let after: WriteMutationSnapshot
    public let collision: WritePreflightCollision?
    public let resource: WriteResourceChangeKind
    public let delta: WriteDeltaKind
    public let backupPolicy: WriteBackupPolicy
    public let canProceed: Bool

    public init(
        target: URL,
        incoming: WriteIncomingContent,
        options: WritePlanOptions = .init(),
        existingData: Data? = nil,
        existingIsBlank: Bool = true,
        overwriteAction: WriteOverwriteAction? = nil,
        before: WriteMutationSnapshot?,
        after: WriteMutationSnapshot,
        collision: WritePreflightCollision?,
        resource: WriteResourceChangeKind,
        delta: WriteDeltaKind,
        backupPolicy: WriteBackupPolicy,
        canProceed: Bool? = nil
    ) {
        let resolvedAction = overwriteAction ?? Self.defaultAction(
            before: before,
            after: after,
            existingData: existingData,
            existingIsBlank: existingIsBlank,
            options: options
        )

        self.target = target
        self.incoming = incoming
        self.options = options
        self.existingData = existingData
        self.existingIsBlank = existingIsBlank
        self.overwriteAction = resolvedAction
        self.before = before
        self.after = after
        self.collision = collision
        self.resource = resource
        self.delta = delta
        self.backupPolicy = backupPolicy
        self.canProceed = canProceed ?? resolvedAction.canProceed
    }

    public var hasCollision: Bool {
        collision != nil
    }

    public var execution: WritePlanExecutionAPI {
        .init(
            plan: self
        )
    }

    @discardableResult
    public func requireClean() throws -> Self {
        guard overwriteAction.canProceed else {
            throw SafePreflightError.refusingToOverwrite(
                [
                    target,
                ]
            )
        }

        return self
    }

    public func mutationRecord(
        operationKind: WriteMutationOperationKind = .unknown,
        metadata: WriteMutationMetadata = .init()
    ) -> WriteMutationRecord {
        var metadata = metadata
        metadata.resource = resource
        metadata.delta = delta

        return .init(
            target: target,
            operationKind: operationKind,
            before: before,
            after: after,
            difference: nil,
            metadata: metadata.raw
        )
    }

    private static func defaultAction(
        before: WriteMutationSnapshot?,
        after: WriteMutationSnapshot,
        existingData: Data?,
        existingIsBlank: Bool,
        options: WritePlanOptions
    ) -> WriteOverwriteAction {
        guard existingData != nil else {
            return .create
        }

        if !existingIsBlank,
           options.existingFilePolicy == .abort {
            return .abort_collision
        }

        if before?.fingerprint == after.fingerprint {
            return .unchanged
        }

        if existingIsBlank {
            return .overwrite_blank
        }

        return .overwrite_nonblank
    }
}

public struct WritePlanExecutionAPI: Sendable {
    public let plan: WritePlan

    public init(
        plan: WritePlan
    ) {
        self.plan = plan
    }

    public func apply(
        writer: StandardWriter,
        options: SafeWriteOptions,
        conflict: @autoclosure () -> SafeFileOverwriteConflict
    ) throws -> SafeWriteResult {
        try WriteExecution(
            writer: writer,
            plan: plan,
            options: options
        ).apply(
            conflict: conflict()
        )
    }
}

public struct WriteExecution: Sendable {
    public let writer: StandardWriter
    public let plan: WritePlan
    public let options: SafeWriteOptions

    public init(
        writer: StandardWriter,
        plan: WritePlan,
        options: SafeWriteOptions
    ) {
        self.writer = writer
        self.plan = plan
        self.options = options
    }

    @discardableResult
    public func apply(
        conflict: @autoclosure () -> SafeFileOverwriteConflict
    ) throws -> SafeWriteResult {
        try writer.execute(
            plan,
            options: options,
            conflict: conflict()
        )
    }
}

public struct StandardWriterPreflightAPI: Sendable {
    public let writer: StandardWriter

    public init(
        writer: StandardWriter
    ) {
        self.writer = writer
    }

    public func data(
        _ data: Data,
        options: SafeWriteOptions = .init()
    ) throws -> WritePlan {
        try writer.writePlan(
            data,
            incomingText: nil,
            options: options
        )
    }

    public func string(
        _ string: String,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) throws -> WritePlan {
        guard let data = string.data(
            using: encoding
        ) else {
            throw SafeFileError.io(
                underlying: NSError(
                    domain: "Writers",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "String encoding failed",
                    ]
                )
            )
        }

        return try writer.writePlan(
            data,
            incomingText: string,
            options: options
        )
    }
}

public extension StandardWriter {
    var preflight: StandardWriterPreflightAPI {
        .init(
            writer: self
        )
    }

    func writePlan(
        _ data: Data,
        incomingText: String? = nil,
        options: SafeWriteOptions = .init()
    ) throws -> WritePlan {
        let fm = FileManager.default
        let existingData = fm.fileExists(
            atPath: url.path
        )
            ? try IntegratedReader.data(
                at: url,
                missingFileReturnsEmpty: false
            )
            : nil

        let before = existingData.map {
            WriteMutationSnapshot(
                data: $0
            )
        }

        let after = WriteMutationSnapshot(
            data: data,
            content: incomingText
        )

        let existingIsBlank = existingData.map {
            $0.isEmpty || Self.isBlankData(
                $0,
                whitespaceCounts: options.whitespaceOnlyIsBlank
            )
        } ?? true

        let optionsSnapshot = WritePlanOptions(
            options
        )

        let action = overwriteAction(
            existingData: existingData,
            existingIsBlank: existingIsBlank,
            before: before,
            after: after,
            options: optionsSnapshot
        )

        let collision: WritePreflightCollision?
        if let existingData,
           !existingIsBlank {
            collision = .init(
                target: url,
                snapshot: .init(
                    data: existingData
                )
            )
        } else {
            collision = nil
        }

        return .init(
            target: url,
            incoming: .init(
                data: data,
                text: incomingText
            ),
            options: optionsSnapshot,
            existingData: existingData,
            existingIsBlank: existingIsBlank,
            overwriteAction: action,
            before: before,
            after: after,
            collision: collision,
            resource: before == nil ? .creation : .update,
            delta: deltaKind(
                before: before,
                after: after
            ),
            backupPolicy: options.resolvedBackupPolicy,
            canProceed: action.canProceed
        )
    }

    private static func isBlankData(
        _ data: Data,
        whitespaceCounts: Bool
    ) -> Bool {
        if data.isEmpty {
            return true
        }

        guard whitespaceCounts else {
            return false
        }

        guard let string = String(
            data: data,
            encoding: .utf8
        ) else {
            return false
        }

        return string.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private func overwriteAction(
        existingData: Data?,
        existingIsBlank: Bool,
        before: WriteMutationSnapshot?,
        after: WriteMutationSnapshot,
        options: WritePlanOptions
    ) -> WriteOverwriteAction {
        guard existingData != nil else {
            return .create
        }

        if !existingIsBlank,
           options.existingFilePolicy == .abort {
            return .abort_collision
        }

        if before?.fingerprint == after.fingerprint {
            return .unchanged
        }

        if existingIsBlank {
            return .overwrite_blank
        }

        return .overwrite_nonblank
    }

    private func deltaKind(
        before: WriteMutationSnapshot?,
        after: WriteMutationSnapshot
    ) -> WriteDeltaKind {
        guard let before else {
            return .addition
        }

        if before.fingerprint == after.fingerprint {
            return .unchanged
        }

        return .replacement
    }
}
