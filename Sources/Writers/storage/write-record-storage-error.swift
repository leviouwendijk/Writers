import Foundation

public enum WriteRecordStorageError: Error, LocalizedError, Sendable {
    case missing_location(
        kind: WriteStoredRecordKind,
        id: UUID
    )

    case kind_mismatch(
        expected: WriteStoredRecordKind,
        actual: WriteStoredRecordKind,
        id: UUID
    )

    public var errorDescription: String? {
        switch self {
        case .missing_location(let kind, let id):
            return "Stored \(kind.rawValue) record \(id.uuidString.lowercased()) has no local location."

        case .kind_mismatch(let expected, let actual, let id):
            return "Stored record \(id.uuidString.lowercased()) has kind '\(actual.rawValue)', but expected '\(expected.rawValue)'."
        }
    }
}
