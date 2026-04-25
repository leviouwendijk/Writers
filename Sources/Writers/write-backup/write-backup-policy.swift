import Foundation

public enum WriteBackupPolicy: String, Codable, Sendable, Hashable, CaseIterable {
    case automatic
    case disabled
    case sibling_file
    case backup_directory
    case external_store
}

public enum WriteBackupStoreError: Error, Sendable, LocalizedError, Hashable {
    case store_required(
        policy: WriteBackupPolicy,
        target: URL
    )

    @available(*, deprecated, renamed: "store_required")
    public static func storeRequired(
        policy: WriteBackupPolicy,
        target: URL
    ) -> Self {
        .store_required(
            policy: policy,
            target: target
        )
    }

    public var errorDescription: String? {
        switch self {
        case .store_required(let policy, let target):
            return "Backup policy '\(policy.rawValue)' requires a WriteBackupStore for: \(target.path)"
        }
    }
}
