public struct StandardEditSiteGuard: Sendable, Codable, Hashable {
    public let before: [String]
    public let after: [String]

    public init(
        before: [String] = [],
        after: [String] = []
    ) {
        self.before = before
        self.after = after
    }

    public var hasContext: Bool {
        !before.isEmpty || !after.isEmpty
    }

    public func matches(
        insertionLine line: Int,
        in lines: [String]
    ) -> Bool {
        let valid = 1...max(
            1,
            lines.count + 1
        )

        guard valid.contains(line) else {
            return false
        }

        let index = line - 1

        if !before.isEmpty {
            guard index >= before.count else {
                return false
            }

            let lowerBound = index - before.count
            let upperBound = index

            guard Array(lines[lowerBound..<upperBound]) == before else {
                return false
            }
        }

        if !after.isEmpty {
            guard index + after.count <= lines.count else {
                return false
            }

            let lowerBound = index
            let upperBound = index + after.count

            guard Array(lines[lowerBound..<upperBound]) == after else {
                return false
            }
        }

        return true
    }
}
