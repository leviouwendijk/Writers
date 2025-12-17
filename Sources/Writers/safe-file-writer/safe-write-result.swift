import Foundation

public struct SafeWriteResult: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let target: URL
    public let wrote: Bool
    public let backupURL: URL?
    public let overwrittenExisting: Bool
    public let bytesWritten: Int

    public init(
        target: URL,
        wrote: Bool,
        backupURL: URL?,
        overwrittenExisting: Bool,
        bytesWritten: Int
    ) {
        self.target = target
        self.wrote = wrote
        self.backupURL = backupURL
        self.overwrittenExisting = overwrittenExisting
        self.bytesWritten = bytesWritten
    }

    public var description: String {
        let p = target.path
        guard wrote else { return "No write performed: \(p)" }
        let suffix = " (\(bytesWritten) bytes)"
        if overwrittenExisting {
            if let bu = backupURL {
                return "Overwrote \(p)\(suffix) (backup: \(bu.lastPathComponent))"
            }
            return "Overwrote \(p)\(suffix)"
        } else {
            return "Created \(p)\(suffix)"
        }
    }

    public var debugDescription: String {
        "SafeWriteResult(target: \(target.path), wrote: \(wrote), overwrittenExisting: \(overwrittenExisting), bytesWritten: \(bytesWritten), backupURL: \(backupURL?.path ?? "nil"))"
    }
}
