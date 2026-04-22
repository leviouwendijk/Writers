import Foundation

public struct StandardEditAnchor: Codable, Sendable, Hashable {
    public let beforeLines: [String]
    public let afterLines: [String]

    public let beforeFingerprint: StandardContentFingerprint?
    public let afterFingerprint: StandardContentFingerprint?

    public let beforeStartLine: Int?
    public let afterStartLine: Int?

    public init(
        beforeLines: [String],
        afterLines: [String],
        beforeFingerprint: StandardContentFingerprint?,
        afterFingerprint: StandardContentFingerprint?,
        beforeStartLine: Int?,
        afterStartLine: Int?
    ) {
        self.beforeLines = beforeLines
        self.afterLines = afterLines
        self.beforeFingerprint = beforeFingerprint
        self.afterFingerprint = afterFingerprint
        self.beforeStartLine = beforeStartLine
        self.afterStartLine = afterStartLine
    }

    public var hasContext: Bool {
        !beforeLines.isEmpty || !afterLines.isEmpty
    }
}
