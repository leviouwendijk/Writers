import Difference

public enum WriteDifference {
    public static func lines(
        old: String,
        new: String,
        oldName: String,
        newName: String
    ) -> TextDifference {
        TextDiffer.diff(
            old: old,
            new: new,
            oldName: oldName,
            newName: newName
        )
    }

    public static func string(
        old: String,
        new: String,
        oldName: String,
        newName: String,
        options: DifferenceRenderOptions = .unified
    ) -> String {
        lines(
            old: old,
            new: new,
            oldName: oldName,
            newName: newName
        ).string(
            options: options
        )
    }

    @available(*, deprecated, message: "Use WriteDifference.lines(old:new:oldName:newName:).string(options:) instead.")
    public static func renderedLines(
        old: String,
        new: String,
        oldName: String,
        newName: String,
        options: DifferenceRenderOptions = .unified
    ) -> String {
        lines(
            old: old,
            new: new,
            oldName: oldName,
            newName: newName
        ).string(
            options: options
        )
    }
}

public extension TextDifference {
    func string(
        options: DifferenceRenderOptions = .unified
    ) -> String {
        DifferenceRenderer.render(
            self,
            options: options
        )
    }

    func layout(
        options: DifferenceRenderOptions = .unified
    ) -> DifferenceLayout {
        DifferenceRenderer.layout(
            self,
            options: options
        )
    }
}

@available(*, deprecated, message: "Use WriteDifference.lines(old:new:oldName:newName:).string() instead.")
public func makeSimpleLineDiff(
    old: String,
    new: String,
    oldName: String,
    newName: String
) -> String {
    WriteDifference.lines(
        old: old,
        new: new,
        oldName: oldName,
        newName: newName
    ).string()
}

@available(*, deprecated, message: "Use WriteDifference.lines(old:new:oldName:newName:).string(options:) instead.")
public func makeSimpleLineDiff(
    old: String,
    new: String,
    oldName: String,
    newName: String,
    options: DifferenceRenderOptions
) -> String {
    WriteDifference.lines(
        old: old,
        new: new,
        oldName: oldName,
        newName: newName
    ).string(
        options: options
    )
}

@available(*, deprecated, message: "Use WriteDifference.lines(old:new:oldName:newName:) instead.")
public func makeStructuredLineDiff(
    old: String,
    new: String,
    oldName: String,
    newName: String
) -> TextDifference {
    WriteDifference.lines(
        old: old,
        new: new,
        oldName: oldName,
        newName: newName
    )
}
