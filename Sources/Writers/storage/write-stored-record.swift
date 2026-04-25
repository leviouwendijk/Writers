import Foundation

public enum WriteStorageLocationKind: String, Codable, Sendable, Hashable, CaseIterable {
    case local_file
    case external
    case memory
    case unknown
}

public struct WriteStorageLocation: Codable, Sendable, Hashable {
    public let kind: WriteStorageLocationKind
    public let value: String
    public let metadata: [String: String]

    public init(
        kind: WriteStorageLocationKind,
        value: String,
        metadata: [String: String] = [:]
    ) {
        self.kind = kind
        self.value = value
        self.metadata = metadata
    }

    public static func local(
        _ url: URL
    ) -> Self {
        .init(
            kind: .local_file,
            value: url.standardizedFileURL.path
        )
    }

    public var localURL: URL? {
        guard kind == .local_file else {
            return nil
        }

        return URL(
            fileURLWithPath: value,
            isDirectory: false
        )
    }
}

public struct WriteStoredRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let kind: WriteStoredRecordKind
    public let target: URL
    public let createdAt: Date
    public let storage: WriteStorageLocation?
    public let metadata: [String: String]

    public init(
        id: UUID,
        kind: WriteStoredRecordKind,
        target: URL,
        createdAt: Date = .init(),
        storage: WriteStorageLocation? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.target = target
        self.createdAt = createdAt
        self.storage = storage
        self.metadata = metadata
    }

    @available(*, deprecated, message: "Use init(..., storage:) instead.")
    public init(
        id: UUID,
        kind: WriteStoredRecordKind,
        target: URL,
        createdAt: Date = .init(),
        location: URL?,
        metadata: [String: String] = [:]
    ) {
        self.init(
            id: id,
            kind: kind,
            target: target,
            createdAt: createdAt,
            storage: location.map(WriteStorageLocation.local),
            metadata: metadata
        )
    }

    @available(*, deprecated, message: "Use storage.localURL instead.")
    public var location: URL? {
        storage?.localURL
    }

    public var isLocal: Bool {
        storage?.localURL != nil
    }

    public func requireLocalURL() throws -> URL {
        guard let url = storage?.localURL else {
            throw WriteRecordStorageError.missing_location(
                kind: kind,
                id: id
            )
        }

        return url
    }
}
