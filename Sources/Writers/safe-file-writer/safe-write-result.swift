import Foundation

public typealias SafeWriteResult = WriteResult

public struct WriteResult: Sendable, Codable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public let target: URL
    public let wrote: Bool
    public let backupURL: URL?
    public let overwrittenExisting: Bool
    public let bytesWritten: Int

    public let backupRecord: WriteBackupRecord?
    public let beforeSnapshot: WriteMutationSnapshot?
    public let afterSnapshot: WriteMutationSnapshot?

    public init(
        target: URL,
        wrote: Bool,
        backupURL: URL?,
        overwrittenExisting: Bool,
        bytesWritten: Int,
        backupRecord: WriteBackupRecord? = nil,
        beforeSnapshot: WriteMutationSnapshot? = nil,
        afterSnapshot: WriteMutationSnapshot? = nil
    ) {
        self.target = target
        self.wrote = wrote
        self.backupURL = backupURL
        self.overwrittenExisting = overwrittenExisting
        self.bytesWritten = bytesWritten
        self.backupRecord = backupRecord
        self.beforeSnapshot = beforeSnapshot
        self.afterSnapshot = afterSnapshot
    }

    public var description: String {
        let p = target.path

        guard wrote else {
            return "No write performed: \(p)"
        }

        let suffix = " (\(bytesWritten) bytes)"

        if overwrittenExisting {
            if let bu = backupURL {
                return "Overwrote \(p)\(suffix) (backup: \(bu.lastPathComponent))"
            }

            return "Overwrote \(p)\(suffix)"
        }

        return "Created \(p)\(suffix)"
    }

    public var debugDescription: String {
        "SafeWriteResult(target: \(target.path), wrote: \(wrote), overwrittenExisting: \(overwrittenExisting), bytesWritten: \(bytesWritten), backupURL: \(backupURL?.path ?? "nil"), backupPolicy: \(backupRecord?.policy.rawValue ?? "none"))"
    }
}
