import Position

public enum StandardEditOperation: Codable, Sendable, Hashable {
    case replaceEntireFile(with: String)

    case append(String, separator: String? = nil)
    case prepend(String, separator: String? = nil)

    case replaceFirst(of: String, with: String)
    case replaceAll(of: String, with: String)
    case replaceUnique(of: String, with: String)

    case replaceLine(Int, with: String)
    case insertLines([String], atLine: Int)
    case replaceLines(LineRange, with: [String])
    case deleteLines(LineRange)
}
