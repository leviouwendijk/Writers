import Foundation

public struct StandardMutationRecordStore: WriteMutationRecordStore {
    public let directoryURL: URL

    public init(
        directory: URL
    ) {
        self.directoryURL = directory
    }

    public init(
        directoryURL: URL
    ) {
        self.init(
            directory: directoryURL
        )
    }

    @discardableResult
    public func store(
        _ record: WriteMutationRecord
    ) throws -> WriteStoredRecord {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let url = recordURL(
            for: record
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
        ]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(
            record
        )

        try data.write(
            to: url,
            options: .atomic
        )

        return .init(
            id: record.id,
            kind: .mutation,
            target: record.target,
            createdAt: record.createdAt,
            storage: .local(url),
            metadata: record.metadata
        )
    }

    public func load(
        _ stored: WriteStoredRecord
    ) throws -> WriteMutationRecord? {
        guard stored.kind == .mutation else {
            throw WriteRecordStorageError.kind_mismatch(
                expected: .mutation,
                actual: stored.kind,
                id: stored.id
            )
        }

        let location = try stored.requireLocalURL()

        guard FileManager.default.fileExists(
            atPath: location.path
        ) else {
            return nil
        }

        return try loadLocal(
            location
        )
    }

    public func list() throws -> [WriteStoredRecord] {
        try listRecordURLs().compactMap { url in
            let record = try loadLocal(
                url
            )

            return .init(
                id: record.id,
                kind: .mutation,
                target: record.target,
                createdAt: record.createdAt,
                storage: .local(url),
                metadata: record.metadata
            )
        }
    }

    public func listRecordURLs() throws -> [URL] {
        guard FileManager.default.fileExists(
            atPath: directoryURL.path
        ) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [
                .skipsHiddenFiles,
            ]
        )
        .filter {
            $0.pathExtension == "json"
        }
        .sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }

    public func recordURL(
        for record: WriteMutationRecord
    ) -> URL {
        let basename = sanitizedBasename(
            for: record.target
        )

        return directoryURL.appendingPathComponent(
            "\(basename).\(record.id.uuidString.lowercased()).mutation.json",
            isDirectory: false
        )
    }

    private func loadLocal(
        _ url: URL
    ) throws -> WriteMutationRecord {
        let data = try Data(
            contentsOf: url
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(
            WriteMutationRecord.self,
            from: data
        )
    }

    private func sanitizedBasename(
        for target: URL
    ) -> String {
        let raw = target.lastPathComponent

        let scalars = raw.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 48...57, 65...90, 97...122:
                return Character(
                    scalar
                )

            case 45, 46, 95:
                return Character(
                    scalar
                )

            default:
                return "_"
            }
        }

        let string = String(
            scalars
        )

        return string.isEmpty ? "mutation" : string
    }
}
