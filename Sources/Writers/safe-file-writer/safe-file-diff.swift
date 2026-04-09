import Difference

public func makeSimpleLineDiff(
    old: String,
    new: String,
    oldName: String,
    newName: String
) -> String {
    DifferenceRenderer.render(
        makeStructuredLineDiff(
            old: old,
            new: new,
            oldName: oldName,
            newName: newName
        )
    )
}

public func makeSimpleLineDiff(
    old: String,
    new: String,
    oldName: String,
    newName: String,
    options: DifferenceRenderOptions
) -> String {
    DifferenceRenderer.render(
        makeStructuredLineDiff(
            old: old,
            new: new,
            oldName: oldName,
            newName: newName
        ),
        options: options
    )
}

public func makeStructuredLineDiff(
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
