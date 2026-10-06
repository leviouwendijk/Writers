import Position

extension StandardEditOperation {
    static func resolvePositionRange(
        _ range: PositionRange,
        in content: String
    ) throws -> Range<String.Index> {
        guard range.start.offset >= 0,
              range.start.offset < range.end.offset
        else {
            throw StandardEditError.invalidPositionRange(
                range
            )
        }

        let valid = PositionRange(
            uncheckedStart: .init(0),
            uncheckedEnd: .init(
                content.count
            )
        )

        guard range.end.offset <= valid.end.offset else {
            throw StandardEditError.positionRangeOutOfBounds(
                range,
                valid: valid
            )
        }

        let lower = content.index(
            content.startIndex,
            offsetBy: range.start.offset
        )
        let upper = content.index(
            content.startIndex,
            offsetBy: range.end.offset
        )

        return lower..<upper
    }
}
