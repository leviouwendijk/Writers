import Foundation
import Writers

struct TestWorkspace: Sendable {
    let root: URL

    init(
        _ name: String
    ) throws {
        let safeName = name
            .replacingOccurrences(
                of: "/",
                with: "-"
            )
            .replacingOccurrences(
                of: " ",
                with: "-"
            )

        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "writers-testflows",
                isDirectory: true
            )
            .appendingPathComponent(
                "\(safeName)-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    func file(
        _ name: String
    ) -> URL {
        root.appendingPathComponent(
            name,
            isDirectory: false
        )
    }

    func directory(
        _ name: String
    ) throws -> URL {
        let url = root.appendingPathComponent(
            name,
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )

        return url
    }

    func read(
        _ url: URL
    ) throws -> String {
        try String(
            contentsOf: url,
            encoding: .utf8
        )
    }

    func exists(
        _ url: URL
    ) -> Bool {
        FileManager.default.fileExists(
            atPath: url.path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(
            at: root
        )
    }
}

final class DirectoryBackupStore: @unchecked Sendable, WriteBackupStore {
    let root: URL

    init(
        root: URL
    ) {
        self.root = root
    }

    func storeBackup(
        _ request: WriteBackupRequest
    ) throws -> WriteBackupRecord {
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let backupURL = root.appendingPathComponent(
            "\(request.id.uuidString.lowercased())-\(request.target.lastPathComponent)",
            isDirectory: false
        )

        try request.data.write(
            to: backupURL,
            options: .atomic
        )

        return .init(
            id: request.id,
            target: request.target,
            storage: .local(backupURL),
            createdAt: request.createdAt,
            originalFingerprint: request.snapshot.fingerprint,
            byteCount: request.snapshot.byteCount,
            policy: request.policy,
            metadata: [
                "store": "directory"
            ]
        )
    }

    func loadBackup(
        _ record: WriteBackupRecord
    ) throws -> Data? {
        guard let backupURL = record.storage?.localURL else {
            return nil
        }

        guard
            FileManager.default.fileExists(
                atPath: backupURL.path
            )
        else {
            return nil
        }

        return try Data(
            contentsOf: backupURL
        )
    }
}
