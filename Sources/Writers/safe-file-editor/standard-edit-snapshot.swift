import Foundation

public struct StandardEditSnapshot: Codable, Sendable, Hashable {
    public let content: String
    public let fingerprint: StandardContentFingerprint

    public init(
        content: String
    ) {
        self.content = content
        self.fingerprint = StandardContentFingerprint.fingerprint(
            for: content
        )
    }

    public init(
        content: String,
        fingerprint: StandardContentFingerprint
    ) {
        self.content = content
        self.fingerprint = fingerprint
    }
}
