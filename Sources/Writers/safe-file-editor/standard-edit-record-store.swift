import Foundation

public struct StandardEditRecordStore: Sendable {
    public let directoryURL: URL

    public init(
        directoryURL: URL
    ) {
        self.directoryURL = directoryURL
    }

    @discardableResult
    public func save(
        _ record: StandardEditRecord,
        createIntermediateDirectories: Bool = true
    ) throws -> URL {
        if createIntermediateDirectories {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }

        let url = recordURL(
            for: record
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(record)
        try data.write(
            to: url,
            options: .atomic
        )

        return url
    }

    public func load(
        _ url: URL
    ) throws -> StandardEditRecord {
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(
            StandardEditRecord.self,
            from: data
        )
    }

    public func listRecordURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func loadAll() throws -> [StandardEditRecord] {
        try listRecordURLs().map(load)
    }

    public func recordURL(
        for record: StandardEditRecord
    ) -> URL {
        let basename = sanitizedBasename(
            for: record.target
        )

        return directoryURL.appendingPathComponent(
            "\(basename).\(record.id.uuidString.lowercased()).edit.json",
            isDirectory: false
        )
    }

    private func sanitizedBasename(
        for target: URL
    ) -> String {
        let raw = target.lastPathComponent

        let scalars = raw.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 48...57, 65...90, 97...122:
                return Character(scalar)

            case 45, 46, 95:
                return Character(scalar)

            default:
                return "_"
            }
        }

        let string = String(scalars)
        return string.isEmpty ? "edit" : string
    }
}
