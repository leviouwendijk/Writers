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
        self.init(
            data: data,
            fingerprint: StandardContentFingerprint.fingerprint(
                for: data
            ),
            content: content,
            storeContent: storeContent
        )
    }

    public init(
        data: Data,
        fingerprint: StandardContentFingerprint,
        content: String? = nil,
        storeContent: Bool = false
    ) {
        let readableContent = content ?? String(
            data: data,
            encoding: .utf8
        )

        self.init(
            fingerprint: fingerprint,
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

        if let contiguousCount = content.utf8
            .withContiguousStorageIfAvailable(
                { buffer in
                    var count = 1

                    guard let baseAddress = buffer.baseAddress else {
                        return count
                    }

                    var index = 0

                    while index < buffer.count {
                        if baseAddress[index] == 0x0A {
                            count += 1
                        }

                        index += 1
                    }

                    return count
                }
            )
        {
            return contiguousCount
        }

        var count = 1

        for byte in content.utf8 {
            if byte == 0x0A {
                count += 1
            }
        }

        return count
    }
}
