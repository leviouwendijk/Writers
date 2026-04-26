import Foundation
import Position

public enum StandardEditError: Error, LocalizedError {
    case emptyMatchString
    case matchNotFound(String)
    case matchNotUnique(String, count: Int)

    case lineOutOfBounds(Int, valid: ClosedRange<Int>?)
    case lineRangeOutOfBounds(LineRange, valid: ClosedRange<Int>?)
    case insertionLineOutOfBounds(Int, valid: ClosedRange<Int>)

    case lineMismatch(
        line: Int,
        expected: String,
        actual: String
    )

    case lineRangeMismatch(
        range: LineRange,
        expected: [String],
        actual: [String]
    )

    case invalidLogicalLine(String)

    public var errorDescription: String? {
        switch self {
        case .emptyMatchString:
            return "Edit match string may not be empty."

        case .matchNotFound(let needle):
            return "Edit match not found: \(needle)"

        case .matchNotUnique(let needle, let count):
            return "Edit match was expected to be unique, but found \(count) matches: \(needle)"

        case .lineOutOfBounds(let line, let valid):
            if let valid {
                return "Edit line \(line) is out of bounds. Valid lines: \(valid.lowerBound)...\(valid.upperBound)"
            }

            return "Edit line \(line) is out of bounds. The file has no editable lines."

        case .lineRangeOutOfBounds(let range, let valid):
            if let valid {
                return "Edit line range \(range) is out of bounds. Valid lines: \(valid.lowerBound)...\(valid.upperBound)"
            }

            return "Edit line range \(range) is out of bounds. The file has no editable lines."

        case .insertionLineOutOfBounds(let line, let valid):
            return "Edit insertion line \(line) is out of bounds. Valid insertion lines: \(valid.lowerBound)...\(valid.upperBound)"

        case .lineMismatch(let line, let expected, let actual):
            return "Edit line \(line) did not match expected content. Expected \(String(reflecting: expected)), found \(String(reflecting: actual))."

        case .lineRangeMismatch(let range, let expected, let actual):
            return "Edit line range \(range) did not match expected content. Expected \(expected.count) line(s), found \(actual.count) line(s)."

        case .invalidLogicalLine(let line):
            return "Edit line payload contains newline characters and is not a single logical line: \(String(reflecting: line))"
        }
    }
}
