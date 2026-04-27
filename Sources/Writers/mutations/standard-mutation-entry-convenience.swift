import Foundation

public extension StandardMutationEntry {
    static func createText(
        at target: URL,
        content: String,
        policy: StandardCreatePolicy = .missing,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) -> Self {
        .create_text(
            .init(
                target: target,
                content: content,
                policy: policy,
                encoding: encoding,
                options: options
            )
        )
    }

    static func replaceText(
        at target: URL,
        content: String,
        policy: StandardReplacePolicy = .existing,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) -> Self {
        .replace_text(
            .init(
                target: target,
                content: content,
                policy: policy,
                encoding: encoding,
                options: options
            )
        )
    }

    static func editText(
        at target: URL,
        operations: [StandardEditOperation],
        mode: StandardEditMode = .sequential,
        constraint: StandardEditConstraint = .unrestricted,
        options: StandardEditApplyOptions = .init()
    ) -> Self {
        .edit_text(
            .init(
                target: target,
                operations: operations,
                mode: mode,
                constraint: constraint,
                options: options
            )
        )
    }

    static func delete(
        at target: URL,
        policy: StandardDeletePolicy = .existing
    ) -> Self {
        .delete(
            .init(
                target: target,
                policy: policy
            )
        )
    }
}
