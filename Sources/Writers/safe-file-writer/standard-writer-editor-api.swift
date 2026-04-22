public extension StandardWriter {
    var editor: StandardEditor {
        .init(
            writer: self
        )
    }
}
