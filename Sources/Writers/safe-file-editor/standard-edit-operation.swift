import Position

public enum StandardEditOperation: Codable, Sendable, Hashable {
    case replaceEntireFile(with: String)

    case append(String, separator: String? = nil)
    case prepend(String, separator: String? = nil)

    case replaceFirst(of: String, with: String)
    case replaceAll(of: String, with: String)
    case replaceUnique(of: String, with: String)

    case replaceLine(Int, with: String)
    case replaceLineGuarded(Int, expected: String, with: String)

    case insertLines([String], atLine: Int)

    case replaceLines(LineRange, with: [String])
    case replaceLinesGuarded(LineRange, expected: [String], with: [String])

    case deleteLines(LineRange)
    case deleteLinesGuarded(LineRange, expected: [String])
}

// ergonomic API surface: 

public extension StandardEditOperation {
    static let file = StandardEditOperationFileSurface()
    static let text = StandardEditOperationTextSurface()
    static let line = StandardEditOperationLineSurface()
    static let lines = StandardEditOperationLinesSurface()
}

public struct StandardEditOperationFileSurface: Sendable {
    public func replace(
        with content: String
    ) -> StandardEditOperation {
        .replaceEntireFile(
            with: content
        )
    }
}

public struct StandardEditOperationTextSurface: Sendable {
    public func append(
        _ content: String,
        separator: String? = nil
    ) -> StandardEditOperation {
        .append(
            content,
            separator: separator
        )
    }

    public func prepend(
        _ content: String,
        separator: String? = nil
    ) -> StandardEditOperation {
        .prepend(
            content,
            separator: separator
        )
    }

    public func replaceFirst(
        _ target: String,
        with replacement: String
    ) -> StandardEditOperation {
        .replaceFirst(
            of: target,
            with: replacement
        )
    }

    public func replaceAll(
        _ target: String,
        with replacement: String
    ) -> StandardEditOperation {
        .replaceAll(
            of: target,
            with: replacement
        )
    }

    public func replaceUnique(
        _ target: String,
        with replacement: String
    ) -> StandardEditOperation {
        .replaceUnique(
            of: target,
            with: replacement
        )
    }
}

public struct StandardEditOperationLineSurface: Sendable {
    public func replace(
        _ line: Int,
        with replacement: String
    ) -> StandardEditOperation {
        .replaceLine(
            line,
            with: replacement
        )
    }

    public func replace(
        _ line: Int,
        expected: String,
        with replacement: String
    ) -> StandardEditOperation {
        .replaceLineGuarded(
            line,
            expected: expected,
            with: replacement
        )
    }
}

public struct StandardEditOperationLinesSurface: Sendable {
    public func insert(
        _ lines: [String],
        at line: Int
    ) -> StandardEditOperation {
        .insertLines(
            lines,
            atLine: line
        )
    }

    public func replace(
        _ range: LineRange,
        with replacement: [String]
    ) -> StandardEditOperation {
        .replaceLines(
            range,
            with: replacement
        )
    }

    public func replace(
        _ range: LineRange,
        expected: [String],
        with replacement: [String]
    ) -> StandardEditOperation {
        .replaceLinesGuarded(
            range,
            expected: expected,
            with: replacement
        )
    }

    public func delete(
        _ range: LineRange
    ) -> StandardEditOperation {
        .deleteLines(
            range
        )
    }

    public func delete(
        _ range: LineRange,
        expected: [String]
    ) -> StandardEditOperation {
        .deleteLinesGuarded(
            range,
            expected: expected
        )
    }
}

