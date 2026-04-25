import Foundation

public enum WriteMutationPayloadPolicy: String, Sendable, Codable, Hashable, CaseIterable {
    case inline
    case external_content
    case metadata_only
}

public struct WriteMutationPayloadRecord: Sendable, Codable, Hashable {
    public let mutationID: UUID
    public let before: WriteStorageLocation?
    public let after: WriteStorageLocation?
    public let diff: WriteStorageLocation?
    public let rollback: WriteStorageLocation?
    public let policy: WriteMutationPayloadPolicy
    public let metadata: [String: String]

    public init(
        mutationID: UUID,
        before: WriteStorageLocation? = nil,
        after: WriteStorageLocation? = nil,
        diff: WriteStorageLocation? = nil,
        rollback: WriteStorageLocation? = nil,
        policy: WriteMutationPayloadPolicy,
        metadata: [String: String] = [:]
    ) {
        self.mutationID = mutationID
        self.before = before
        self.after = after
        self.diff = diff
        self.rollback = rollback
        self.policy = policy
        self.metadata = metadata
    }
}

public extension StandardMutationRecordStore {
    struct Payloads: Sendable {
        public let directoryURL: URL

        public init(
            directoryURL: URL
        ) {
            self.directoryURL = directoryURL
        }

        public func store(
            _ record: WriteMutationRecord,
            policy: WriteMutationPayloadPolicy = .external_content
        ) throws -> WriteMutationPayloadRecord {
            guard policy == .external_content else {
                return .init(
                    mutationID: record.id,
                    policy: policy
                )
            }

            let before = try storeContent(
                record.before?.content,
                mutationID: record.id,
                name: "before.txt"
            )

            let after = try storeContent(
                record.after?.content,
                mutationID: record.id,
                name: "after.txt"
            )

            let rollback = try storeRollback(
                record.rollbackOperations,
                mutationID: record.id
            )

            return .init(
                mutationID: record.id,
                before: before,
                after: after,
                rollback: rollback,
                policy: policy,
                metadata: record.metadata
            )
        }

        public func storeContent(
            _ content: String?,
            mutationID: UUID,
            name: String
        ) throws -> WriteStorageLocation? {
            guard let content else {
                return nil
            }

            let url = payloadURL(
                mutationID: mutationID,
                name: name
            )

            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            try Data(
                content.utf8
            ).write(
                to: url,
                options: .atomic
            )

            return .local(
                url
            )
        }

        public func storeRollback(
            _ operations: [StandardEditOperation],
            mutationID: UUID
        ) throws -> WriteStorageLocation? {
            guard !operations.isEmpty else {
                return nil
            }

            let url = payloadURL(
                mutationID: mutationID,
                name: "rollback.json"
            )

            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys,
            ]

            let data = try encoder.encode(
                operations
            )

            try data.write(
                to: url,
                options: .atomic
            )

            return .local(
                url
            )
        }

        private func payloadURL(
            mutationID: UUID,
            name: String
        ) -> URL {
            directoryURL
                .appendingPathComponent(
                    mutationID.uuidString.lowercased(),
                    isDirectory: true
                )
                .appendingPathComponent(
                    name,
                    isDirectory: false
                )
        }
    }

    var payloads: Payloads {
        .init(
            directoryURL: directoryURL.appendingPathComponent(
                "payloads",
                isDirectory: true
            )
        )
    }
}
