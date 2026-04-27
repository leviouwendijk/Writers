import Foundation
import Path

public extension WorkspaceMutationEntry {
    static func createText(
        at target: String,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        content: String,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) -> Self {
        .create_text(
            .init(
                target: .raw(target),
                rootIdentifier: rootIdentifier,
                content: content,
                encoding: encoding,
                options: options
            )
        )
    }

    static func createText(
        at target: StandardPath,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        content: String,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .init()
    ) -> Self {
        .create_text(
            .init(
                target: .standard(target),
                rootIdentifier: rootIdentifier,
                content: content,
                encoding: encoding,
                options: options
            )
        )
    }

    static func replaceText(
        at target: String,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        content: String,
        policy: StandardReplacePolicy = .existing,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) -> Self {
        .replace_text(
            .init(
                target: .raw(target),
                rootIdentifier: rootIdentifier,
                content: content,
                policy: policy,
                encoding: encoding,
                options: options
            )
        )
    }

    static func replaceText(
        at target: StandardPath,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        content: String,
        policy: StandardReplacePolicy = .existing,
        encoding: String.Encoding = .utf8,
        options: SafeWriteOptions = .overwrite
    ) -> Self {
        .replace_text(
            .init(
                target: .standard(target),
                rootIdentifier: rootIdentifier,
                content: content,
                policy: policy,
                encoding: encoding,
                options: options
            )
        )
    }

    static func editText(
        at target: String,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        operations: [StandardEditOperation],
        mode: StandardEditMode = .sequential,
        constraint: StandardEditConstraint = .unrestricted,
        options: StandardEditApplyOptions = .init()
    ) -> Self {
        .edit_text(
            .init(
                target: .raw(target),
                rootIdentifier: rootIdentifier,
                operations: operations,
                mode: mode,
                constraint: constraint,
                options: options
            )
        )
    }

    static func editText(
        at target: StandardPath,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        operations: [StandardEditOperation],
        mode: StandardEditMode = .sequential,
        constraint: StandardEditConstraint = .unrestricted,
        options: StandardEditApplyOptions = .init()
    ) -> Self {
        .edit_text(
            .init(
                target: .standard(target),
                rootIdentifier: rootIdentifier,
                operations: operations,
                mode: mode,
                constraint: constraint,
                options: options
            )
        )
    }

    static func delete(
        at target: String,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        policy: StandardDeletePolicy = .existing,
        type: PathSegmentType? = .file
    ) -> Self {
        .delete(
            .init(
                target: .raw(target),
                rootIdentifier: rootIdentifier,
                policy: policy,
                type: type
            )
        )
    }

    static func delete(
        at target: StandardPath,
        rootIdentifier: PathAccessRootIdentifier? = nil,
        policy: StandardDeletePolicy = .existing,
        type: PathSegmentType? = .file
    ) -> Self {
        .delete(
            .init(
                target: .standard(target),
                rootIdentifier: rootIdentifier,
                policy: policy,
                type: type
            )
        )
    }
}
