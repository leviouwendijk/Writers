import Position

/// Operations representable by the snapshot-based coordinated editor.
/// General StandardEditOperation values are narrowed at the boundary.
public enum StandardCoordinatedEditOperation: Sendable, Codable, Hashable {
    case replaceLine(Int, with: String)
    case replaceLineGuarded(Int, expected: String, with: String)
    case insertLines([String], atLine: Int)
    case insertLinesGuarded([String], atLine: Int, site: StandardEditSiteGuard)
    case replaceLines(LineRange, with: [String])
    case replaceLinesGuarded(LineRange, expected: [String], with: [String])
    case deleteLines(LineRange)
    case deleteLinesGuarded(LineRange, expected: [String])

    public init(_ operation: StandardEditOperation) throws {
        switch operation {
        case .replaceLine(let line, let content):
            self = .replaceLine(line, with: content)
        case .replaceLineGuarded(let line, let expected, let content):
            self = .replaceLineGuarded(line, expected: expected, with: content)
        case .insertLines(let lines, let at):
            self = .insertLines(lines, atLine: at)
        case .insertLinesGuarded(let lines, let at, let site):
            self = .insertLinesGuarded(lines, atLine: at, site: site)
        case .replaceLines(let range, let lines):
            self = .replaceLines(range, with: lines)
        case .replaceLinesGuarded(let range, let expected, let lines):
            self = .replaceLinesGuarded(range, expected: expected, with: lines)
        case .deleteLines(let range):
            self = .deleteLines(range)
        case .deleteLinesGuarded(let range, let expected):
            self = .deleteLinesGuarded(range, expected: expected)
        default:
            throw StandardEditCoordinationError.unsupported_operation(operation.kind)
        }
    }

    public var standard_operation: StandardEditOperation {
        switch self {
        case .replaceLine(let line, let content):
            return .replaceLine(line, with: content)
        case .replaceLineGuarded(let line, let expected, let content):
            return .replaceLineGuarded(line, expected: expected, with: content)
        case .insertLines(let lines, let at):
            return .insertLines(lines, atLine: at)
        case .insertLinesGuarded(let lines, let at, let site):
            return .insertLinesGuarded(lines, atLine: at, site: site)
        case .replaceLines(let range, let lines):
            return .replaceLines(range, with: lines)
        case .replaceLinesGuarded(let range, let expected, let lines):
            return .replaceLinesGuarded(range, expected: expected, with: lines)
        case .deleteLines(let range):
            return .deleteLines(range)
        case .deleteLinesGuarded(let range, let expected):
            return .deleteLinesGuarded(range, expected: expected)
        }
    }
}
