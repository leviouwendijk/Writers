import Foundation

public struct WritePreflightCollision: Sendable, Codable, Hashable {
    public let target: URL
    public let snapshot: WriteMutationSnapshot

    public init(
        target: URL,
        snapshot: WriteMutationSnapshot
    ) {
        self.target = target
        self.snapshot = snapshot
    }
}

public struct WritePreflightResult: Sendable, Codable, Hashable {
    public let targets: [URL]
    public let collisions: [WritePreflightCollision]
    public let backupRecords: [WriteBackupRecord]
    public let resourceChangeKind: WriteResourceChangeKind
    public let backupPolicy: WriteBackupPolicy
    public let canProceed: Bool

    public init(
        targets: [URL],
        collisions: [WritePreflightCollision],
        backupRecords: [WriteBackupRecord],
        resourceChangeKind: WriteResourceChangeKind,
        backupPolicy: WriteBackupPolicy,
        canProceed: Bool
    ) {
        self.targets = targets
        self.collisions = collisions
        self.backupRecords = backupRecords
        self.resourceChangeKind = resourceChangeKind
        self.backupPolicy = backupPolicy
        self.canProceed = canProceed
    }

    public var hasCollisions: Bool {
        !collisions.isEmpty
    }

    @discardableResult
    public func requireClean() throws -> Self {
        guard canProceed else {
            throw SafePreflightError.refusingToOverwrite(
                collisions.map(\.target)
            )
        }

        return self
    }
}

public enum WriteTargetPreflight {
    private struct CollisionPayload {
        let target: URL
        let data: Data
        let snapshot: WriteMutationSnapshot

        var publicCollision: WritePreflightCollision {
            .init(
                target: target,
                snapshot: snapshot
            )
        }
    }

    private struct Inspection {
        let targets: [URL]
        let existingCount: Int
        let collisions: [CollisionPayload]
    }

    public static func scan(
        _ target: URL,
        options: SafeWriteOptions
    ) throws -> WritePreflightResult {
        try scan(
            [
                target,
            ],
            options: options
        )
    }

    public static func scan(
        _ targets: [URL],
        options: SafeWriteOptions
    ) throws -> WritePreflightResult {
        let inspection = try inspect(
            targets,
            options: options
        )

        return result(
            inspection,
            options: options,
            backupRecords: []
        )
    }

    public static func prepare(
        _ target: URL,
        options: SafeWriteOptions
    ) throws -> WritePreflightResult {
        try prepare(
            [
                target,
            ],
            options: options
        )
    }

    public static func prepare(
        _ targets: [URL],
        options: SafeWriteOptions
    ) throws -> WritePreflightResult {
        let inspection = try inspect(
            targets,
            options: options
        )

        let scanResult = result(
            inspection,
            options: options,
            backupRecords: []
        )

        guard scanResult.canProceed,
              options.existingFilePolicy == .overwrite,
              scanResult.backupPolicy != .disabled
        else {
            return scanResult
        }

        let backups = try makeBackups(
            for: inspection.collisions,
            policy: scanResult.backupPolicy,
            options: options
        )

        return result(
            inspection,
            options: options,
            backupRecords: backups
        )
    }

    private static func inspect(
        _ targets: [URL],
        options: SafeWriteOptions
    ) throws -> Inspection {
        let fm = FileManager.default
        var existingCount = 0
        var collisions: [CollisionPayload] = []

        for target in targets {
            guard fm.fileExists(
                atPath: target.path
            ) else {
                continue
            }

            existingCount += 1

            guard let data = try? Data(
                contentsOf: target,
                options: .uncached
            ) else {
                continue
            }

            guard !isBlankData(
                data,
                whitespaceCounts: options.whitespaceOnlyIsBlank
            ) else {
                continue
            }

            collisions.append(
                .init(
                    target: target,
                    data: data,
                    snapshot: .init(
                        data: data
                    )
                )
            )
        }

        return .init(
            targets: targets,
            existingCount: existingCount,
            collisions: collisions
        )
    }

    private static func result(
        _ inspection: Inspection,
        options: SafeWriteOptions,
        backupRecords: [WriteBackupRecord]
    ) -> WritePreflightResult {
        let backupPolicy = options.resolvedBackupPolicy
        let canProceed = inspection.collisions.isEmpty
            || options.existingFilePolicy == .overwrite

        return .init(
            targets: inspection.targets,
            collisions: inspection.collisions.map(\.publicCollision),
            backupRecords: backupRecords,
            resourceChangeKind: resourceChangeKind(
                targetCount: inspection.targets.count,
                existingCount: inspection.existingCount
            ),
            backupPolicy: backupPolicy,
            canProceed: canProceed
        )
    }

    private static func makeBackups(
        for collisions: [CollisionPayload],
        policy: WriteBackupPolicy,
        options: SafeWriteOptions
    ) throws -> [WriteBackupRecord] {
        let ts = SafeFile(
            URL(fileURLWithPath: "/dev/null")
        ).timestampString()

        var records: [WriteBackupRecord] = []

        for collision in collisions {
            if let record = try makeBackup(
                for: collision,
                policy: policy,
                options: options,
                timestamp: ts
            ) {
                records.append(
                    record
                )
            }
        }

        return records
    }

    private static func makeBackup(
        for collision: CollisionPayload,
        policy: WriteBackupPolicy,
        options: SafeWriteOptions,
        timestamp: String
    ) throws -> WriteBackupRecord? {
        let fm = FileManager.default

        switch policy {
        case .automatic,
             .disabled:
            return nil

        case .sibling_file:
            let baseBackup = collision.target
                .deletingLastPathComponent()
                .appendingPathComponent(
                    collision.target.lastPathComponent + options.backupSuffix,
                    isDirectory: false
                )

            let backupURL: URL
            if fm.fileExists(
                atPath: baseBackup.path
            ) {
                backupURL = collision.target
                    .deletingLastPathComponent()
                    .appendingPathComponent(
                        collision.target.lastPathComponent + ".\(timestamp)" + options.backupSuffix,
                        isDirectory: false
                    )
            } else {
                backupURL = baseBackup
            }

            try fm.copyItem(
                at: collision.target,
                to: backupURL
            )

            return .init(
                target: collision.target,
                storage: .local(
                    backupURL
                ),
                originalFingerprint: collision.snapshot.fingerprint,
                byteCount: collision.snapshot.byteCount,
                policy: policy
            )

        case .backup_directory:
            let writer = SafeFile(
                collision.target
            )
            let setDir = try writer.ensureBackupSetDir(
                options: options,
                timestamp: timestamp
            )
            let dst = setDir.appendingPathComponent(
                collision.target.lastPathComponent,
                isDirectory: false
            )

            if fm.fileExists(
                atPath: dst.path
            ) {
                try? fm.removeItem(
                    at: dst
                )
            }

            try fm.copyItem(
                at: collision.target,
                to: dst
            )

            try writer.pruneBackupSets(
                baseDir: setDir.deletingLastPathComponent(),
                prefix: options.backupSetPrefix,
                keep: options.maxBackupSets
            )

            return .init(
                target: collision.target,
                storage: .local(
                    dst
                ),
                originalFingerprint: collision.snapshot.fingerprint,
                byteCount: collision.snapshot.byteCount,
                policy: policy
            )

        case .external_store:
            guard let backupStore = options.backupStore else {
                throw WriteBackupStoreError.store_required(
                    policy: policy,
                    target: collision.target
                )
            }

            return try backupStore.storeBackup(
                .init(
                    target: collision.target,
                    data: collision.data,
                    snapshot: collision.snapshot,
                    policy: policy
                )
            )
        }
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

    private static func resourceChangeKind(
        targetCount: Int,
        existingCount: Int
    ) -> WriteResourceChangeKind {
        guard targetCount > 0 else {
            return .unknown
        }

        if existingCount == 0 {
            return .creation
        }

        if existingCount == targetCount {
            return .update
        }

        return .unknown
    }
}

public enum WritePreflight {
    public static func run(
        _ target: URL,
        options: SafeWriteOptions
    ) throws -> WritePreflightResult {
        try run(
            [
                target,
            ],
            options: options
        )
    }

    public static func run(
        _ targets: [URL],
        options: SafeWriteOptions
    ) throws -> WritePreflightResult {
        try WriteTargetPreflight.prepare(
            targets,
            options: options
        )
    }
}

public func preflightSafeWrite(
    _ targets: [URL],
    options: SafeWriteOptions
) throws {
    _ = try WriteTargetPreflight.scan(
        targets,
        options: options
    ).requireClean()
}
