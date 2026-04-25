public struct WriteTextLines: Sendable, Codable, Hashable {
    public let lines: [String]

    public init(
        _ content: String
    ) {
        guard !content.isEmpty else {
            self.lines = []
            return
        }

        self.lines = content
            .replacingOccurrences(
                of: "\r\n",
                with: "\n"
            )
            .replacingOccurrences(
                of: "\r",
                with: "\n"
            )
            .split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            .map(String.init)
    }

    public init(
        lines: [String]
    ) {
        self.lines = lines
    }

    public func string() -> String {
        Self.string(
            lines
        )
    }

    public static func string(
        _ lines: [String]
    ) -> String {
        guard !lines.isEmpty else {
            return ""
        }

        return lines.joined(
            separator: "\n"
        )
    }
}
