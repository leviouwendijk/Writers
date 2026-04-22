import Foundation

public struct StandardContentFingerprint: Codable, Sendable, Hashable, CustomStringConvertible {
    public let algorithm: String
    public let value: String

    public init(
        algorithm: String,
        value: String
    ) {
        self.algorithm = algorithm
        self.value = value
    }

    public var description: String {
        "\(algorithm):\(value)"
    }

    public static func fingerprint(
        for content: String
    ) -> Self {
        fnv1a64(content)
    }

    public static func fingerprint(
        forLines lines: [String]
    ) -> Self? {
        guard !lines.isEmpty else {
            return nil
        }

        return fingerprint(
            for: lines.joined(separator: "\n")
        )
    }

    private static func fnv1a64(
        _ string: String
    ) -> Self {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }

        let value = String(
            format: "%016llx",
            hash
        )

        return .init(
            algorithm: "fnv1a64",
            value: value
        )
    }
}
