import Difference
import Foundation

public typealias StandardMutationDiffPathNameProvider = @Sendable (
    StandardPlannedMutation
) -> String

public struct StandardMutationDiffPreview: Sendable, Codable, Hashable {
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
}

public extension StandardMutationPlan {
    func diffPreview(
        contextLineCount: Int = 3,
        pathName: StandardMutationDiffPathNameProvider? = nil
    ) -> StandardMutationDiffPreview {
        let sections = entries.map { entry in
            entry.diffPreview(
                contextLineCount: contextLineCount,
                pathName: pathName?(
                    entry
                ) ?? entry.target.lastPathComponent
            )
        }

        let text = sections
            .map(\.text)
            .joined(
                separator: "\n\n"
            )

        let layout = combinedLayout(
            sections
        )

        return .init(
            title: "Preview diff for \(entries.count) file mutation(s)",
            contextLineCount: contextLineCount,
            text: text,
            layout: layout,
            insertedLineCount: sections.reduce(0) {
                $0 + $1.insertedLineCount
            },
            deletedLineCount: sections.reduce(0) {
                $0 + $1.deletedLineCount
            }
        )
    }
}

public extension StandardPlannedMutation {
    func diffPreview(
        contextLineCount: Int = 3,
        pathName: String? = nil
    ) -> StandardTextDiffPreview {
        let presentationPath = pathName ?? target.lastPathComponent
        let oldName = "a/\(presentationPath)"
        let newName = "b/\(presentationPath)"

        guard let before = textualPreviewContent(
            for: before
        ),
              let after = textualPreviewContent(
                for: after
              )
        else {
            return .fallback(
                title: "Preview diff for \(presentationPath)",
                contextLineCount: contextLineCount,
                text: """
                --- \(oldName)
                +++ \(newName)
                # non-text textual preview unavailable
                resource: \(resource.rawValue)
                delta: \(delta.rawValue)
                """
            )
        }

        return .text(
            old: before,
            new: after,
            oldName: oldName,
            newName: newName,
            title: "Preview diff for \(presentationPath)",
            contextLineCount: contextLineCount
        )
    }
}

private func textualPreviewContent(
    for state: StandardResourceState
) -> String? {
    switch state {
    case .missing:
        return ""

    case .text(let value):
        return value.content

    case .data:
        return nil
    }
}

private func combinedLayout(
    _ sections: [StandardTextDiffPreview]
) -> DifferenceLayout? {
    let lines = combinedLayoutLines(
        sections
    )

    guard !lines.isEmpty else {
        return nil
    }

    return DifferenceLayout(
        lines: lines
    )
}

private func combinedLayoutLines(
    _ sections: [StandardTextDiffPreview]
) -> [DifferenceLayout.Line] {
    var lines: [DifferenceLayout.Line] = []

    for section in sections {
        if !lines.isEmpty {
            lines.append(
                .init(
                    role: .separator,
                    text: ""
                )
            )
        }

        if let layout = section.layout,
           !layout.isEmpty {
            lines.append(
                contentsOf: layout.lines
            )
        } else if !section.text.isEmpty {
            lines.append(
                contentsOf: fallbackLayoutLines(
                    section.text
                )
            )
        }
    }

    return lines
}

private func fallbackLayoutLines(
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
