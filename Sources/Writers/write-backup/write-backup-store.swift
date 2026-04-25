import Foundation

public struct WriteBackupRequest: Sendable {
    public let id: UUID
    public let target: URL
    public let createdAt: Date
    public let data: Data
    public let snapshot: WriteMutationSnapshot
    public let policy: WriteBackupPolicy

    public init(
        id: UUID = .init(),
        target: URL,
        createdAt: Date = .init(),
        data: Data,
        snapshot: WriteMutationSnapshot? = nil,
        policy: WriteBackupPolicy
    ) {
        self.id = id
        self.target = target
        self.createdAt = createdAt
        self.data = data
        self.snapshot = snapshot ?? .init(
            data: data
        )
        self.policy = policy
    }
}

public struct WriteBackupRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let target: URL
    public let storage: WriteStorageLocation?
    public let createdAt: Date
    public let originalFingerprint: StandardContentFingerprint
    public let byteCount: Int
    public let policy: WriteBackupPolicy
    public let metadata: [String: String]

    public init(
        id: UUID = .init(),
        target: URL,
        storage: WriteStorageLocation? = nil,
        createdAt: Date = .init(),
        originalFingerprint: StandardContentFingerprint,
        byteCount: Int,
        policy: WriteBackupPolicy,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.target = target
        self.storage = storage
        self.createdAt = createdAt
        self.originalFingerprint = originalFingerprint
        self.byteCount = byteCount
        self.policy = policy
        self.metadata = metadata
    }

    public init(
        id: UUID = .init(),
        target: URL,
        backupURL: URL?,
        createdAt: Date = .init(),
        originalFingerprint: StandardContentFingerprint,
        byteCount: Int,
        policy: WriteBackupPolicy,
        metadata: [String: String] = [:]
    ) {
        self.init(
            id: id,
            target: target,
            storage: backupURL.map(WriteStorageLocation.local),
            createdAt: createdAt,
            originalFingerprint: originalFingerprint,
            byteCount: byteCount,
            policy: policy,
            metadata: metadata
        )
    }

    @available(*, deprecated, message: "Use storage.localURL instead.")
    public var backupURL: URL? {
        storage?.localURL
    }

    public var isLocal: Bool {
        storage?.localURL != nil
    }
}

private extension WriteBackupRecord {
    enum CodingKeys: String, CodingKey {
        case id
        case target
        case backupURL
        case storage
        case createdAt
        case originalFingerprint
        case byteCount
        case policy
        case metadata
    }
}

public extension WriteBackupRecord {
    init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        let backupURL = try container.decodeIfPresent(
            URL.self,
            forKey: .backupURL
        )

        self.init(
            id: try container.decode(
                UUID.self,
                forKey: .id
            ),
            target: try container.decode(
                URL.self,
                forKey: .target
            ),
            storage: try container.decodeIfPresent(
                WriteStorageLocation.self,
                forKey: .storage
            ) ?? backupURL.map(WriteStorageLocation.local),
            createdAt: try container.decode(
                Date.self,
                forKey: .createdAt
            ),
            originalFingerprint: try container.decode(
                StandardContentFingerprint.self,
                forKey: .originalFingerprint
            ),
            byteCount: try container.decode(
                Int.self,
                forKey: .byteCount
            ),
            policy: try container.decode(
                WriteBackupPolicy.self,
                forKey: .policy
            ),
            metadata: try container.decodeIfPresent(
                [String: String].self,
                forKey: .metadata
            ) ?? [:]
        )
    }

    func encode(
        to encoder: any Encoder
    ) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        try container.encode(
            id,
            forKey: .id
        )
        try container.encode(
            target,
            forKey: .target
        )
        try container.encodeIfPresent(
            storage?.localURL,
            forKey: .backupURL
        )
        try container.encodeIfPresent(
            storage,
            forKey: .storage
        )
        try container.encode(
            createdAt,
            forKey: .createdAt
        )
        try container.encode(
            originalFingerprint,
            forKey: .originalFingerprint
        )
        try container.encode(
            byteCount,
            forKey: .byteCount
        )
        try container.encode(
            policy,
            forKey: .policy
        )
        try container.encode(
            metadata,
            forKey: .metadata
        )
    }
}

public protocol WriteBackupStore: Sendable {
    func storeBackup(
        _ request: WriteBackupRequest
    ) throws -> WriteBackupRecord

    func loadBackup(
        _ record: WriteBackupRecord
    ) throws -> Data?
}
