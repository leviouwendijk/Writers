import Foundation
import Writers

struct MutationSummary: Sendable, Codable, Hashable {
    var target: String
    var operation: String

    var before: SnapshotSummary?
    var after: SnapshotSummary?
    var difference: DifferenceSummary?
    var backup: BackupSummary?

    var rollbackOperationCount: Int
    var hasRollbackGuard: Bool
    var metadata: [String: String]

    init(
        _ record: WriteMutationRecord
    ) {
        self.target = record.target.lastPathComponent
        self.operation = record.operationKind.rawValue

        self.before = record.before.map(SnapshotSummary.init)
        self.after = record.after.map(SnapshotSummary.init)
        self.difference = record.difference.map(DifferenceSummary.init)
        self.backup = record.backupRecord.map(BackupSummary.init)

        self.rollbackOperationCount = record.rollbackOperations.count
        self.hasRollbackGuard = record.rollbackGuard != nil
        self.metadata = record.metadata
    }

    func render() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        let data = try encoder.encode(
            self
        )

        return String(
            decoding: data,
            as: UTF8.self
        )
    }
}

struct SnapshotSummary: Sendable, Codable, Hashable {
    var fingerprintAlgorithm: String
    var fingerprintValue: String
    var byteCount: Int
    var lineCount: Int?
    var hasContent: Bool

    init(
        _ snapshot: WriteMutationSnapshot
    ) {
        self.fingerprintAlgorithm = snapshot.fingerprint.algorithm
        self.fingerprintValue = snapshot.fingerprint.value
        self.byteCount = snapshot.byteCount
        self.lineCount = snapshot.lineCount
        self.hasContent = snapshot.content != nil
    }
}

struct DifferenceSummary: Sendable, Codable, Hashable {
    var insertions: Int
    var deletions: Int
    var changeCount: Int
    var hasChanges: Bool

    init(
        _ summary: WriteMutationDifferenceSummary
    ) {
        self.insertions = summary.insertions
        self.deletions = summary.deletions
        self.changeCount = summary.changeCount
        self.hasChanges = summary.hasChanges
    }
}

struct BackupSummary: Sendable, Codable, Hashable {
    var policy: String
    var hasBackupURL: Bool
    var byteCount: Int
    var fingerprintAlgorithm: String
    var fingerprintValue: String
    var metadata: [String: String]

    init(
        _ record: WriteBackupRecord
    ) {
        self.policy = record.policy.rawValue
        self.hasBackupURL = record.storage?.localURL != nil
        self.byteCount = record.byteCount
        self.fingerprintAlgorithm = record.originalFingerprint.algorithm
        self.fingerprintValue = record.originalFingerprint.value
        self.metadata = record.metadata
    }
}
