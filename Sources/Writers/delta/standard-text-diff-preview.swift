import Difference
import Foundation

public struct StandardTextDiffPreview: Sendable, Codable, Hashable {
    public let title: String?
    public let contextLineCount: Int
    public let text: String
    public let layout: DifferenceLayout?
    public let insertedLineCount: Int
    public let deletedLineCount: Int

    public init(
        title: String? = nil,
        contextLineCount: Int = 3,
        text: String,
        layout: DifferenceLayout? = nil,
        insertedLineCount: Int = 0,
        deletedLineCount: Int = 0
    ) {
        self.title = title
        self.contextLineCount = max(
            0,
            contextLineCount
        )
        self.text = text
        self.layout = layout
        self.insertedLineCount = max(
            0,
            insertedLineCount
        )
        self.deletedLineCount = max(
            0,
            deletedLineCount
        )
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty && (layout?.isEmpty ?? true)
    }

    public var changedLineCount: Int {
        insertedLineCount + deletedLineCount
    }

    public static func text(
        old: String,
        new: String,
        oldName: String,
        newName: String,
        title: String? = nil,
        contextLineCount: Int = 3
    ) -> Self {
        let difference = TextDiffer.diff(
            old: old,
            new: new,
            oldName: oldName,
            newName: newName
        )

        return text(
            difference,
            title: title,
            contextLineCount: contextLineCount
        )
    }

    public static func text(
        _ difference: TextDifference,
        title: String? = nil,
        contextLineCount: Int = 3
    ) -> Self {
        let options = DifferenceRenderOptions(
            showHeader: true,
            showUnchangedLines: false,
            contextLineCount: contextLineCount
        )

        guard difference.hasChanges else {
            let rendered = """
            --- \(difference.oldName)
            +++ \(difference.newName)
            # no textual changes
            """

            return .init(
                title: title,
                contextLineCount: contextLineCount,
                text: rendered,
                layout: fallbackLayout(
                    rendered
                ),
                insertedLineCount: 0,
                deletedLineCount: 0
            )
        }

        let layout = DifferenceRenderer.layout(
            difference,
            options: options
        )

        return .init(
            title: title,
            contextLineCount: contextLineCount,
            text: DifferenceRenderer.render(
                layout,
                options: options
            ),
            layout: layout,
            insertedLineCount: difference.insertions,
            deletedLineCount: difference.deletions
        )
    }

    public static func fallback(
        title: String? = nil,
        contextLineCount: Int = 3,
        text: String,
        insertedLineCount: Int = 0,
        deletedLineCount: Int = 0
    ) -> Self {
        .init(
            title: title,
            contextLineCount: contextLineCount,
            text: text,
            layout: fallbackLayout(
                text
            ),
            insertedLineCount: insertedLineCount,
            deletedLineCount: deletedLineCount
        )
    }
}

private extension StandardTextDiffPreview {
    static func fallbackLayout(
        _ text: String
    ) -> DifferenceLayout {
        DifferenceLayout(
            lines: fallbackLayoutLines(
                text
            )
        )
    }

    static func fallbackLayoutLines(
        _ text: String
    ) -> [DifferenceLayout.Line] {
        text.components(
            separatedBy: "\n"
        ).map { line in
            if line.hasPrefix("--- ") {
                return .init(
                    role: .headerOld,
                    text: String(
                        line.dropFirst(4)
                    )
                )
            }

            if line.hasPrefix("+++ ") {
                return .init(
                    role: .headerNew,
                    text: String(
                        line.dropFirst(4)
                    )
                )
            }

            if line.hasPrefix("+") {
                return .init(
                    role: .insert,
                    text: String(
                        line.dropFirst()
                    )
                )
            }

            if line.hasPrefix("-") {
                return .init(
                    role: .delete,
                    text: String(
                        line.dropFirst()
                    )
                )
            }

            if line.hasPrefix("#") {
                return .init(
                    role: .separator,
                    text: line
                )
            }

            return .init(
                role: .equal,
                text: line
            )
        }
    }
}
