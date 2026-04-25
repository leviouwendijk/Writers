import Foundation

public struct WriteMutationSnapshot: Codable, Sendable, Hashable {
    public let fingerprint: StandardContentFingerprint
    public let byteCount: Int
    public let lineCount: Int?
    public let content: String?

    public init(
        fingerprint: StandardContentFingerprint,
        byteCount: Int,
        lineCount: Int? = nil,
        content: String? = nil
    ) {
        self.fingerprint = fingerprint
        self.byteCount = byteCount
        self.lineCount = lineCount
        self.content = content
    }

    public init(
        data: Data,
        content: String? = nil,
        storeContent: Bool = false
    ) {
        let readableContent = content ?? String(
            data: data,
            encoding: .utf8
        )

        self.init(
            fingerprint: StandardContentFingerprint.fingerprint(
                for: data
            ),
            byteCount: data.count,
            lineCount: readableContent.map(Self.lineCount),
            content: storeContent ? readableContent : nil
        )
    }

    public init(
        content: String,
        storeContent: Bool = false,
        encoding: String.Encoding = .utf8
    ) {
        let data = content.data(
            using: encoding
        ) ?? Data(
            content.utf8
        )

        self.init(
            data: data,
            content: content,
            storeContent: storeContent
        )
    }

    private static func lineCount(
        _ content: String
    ) -> Int {
        guard !content.isEmpty else {
            return 0
        }

        return content
            .split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            .count
    }
}
