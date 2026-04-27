import Position

public enum StandardEditLimit: Sendable, Codable, Hashable {
    case unlimited
    case limited(Int)

    public func allows(
        _ value: Int
    ) -> Bool {
        switch self {
        case .unlimited:
            return true

        case .limited(let limit):
            return value <= limit
        }
    }

    public var value: Int? {
        switch self {
        case .unlimited:
            return nil

        case .limited(let value):
            return value
        }
    }
}

public struct StandardEditBudget: Sendable, Codable, Hashable {
    public var operations: StandardEditLimit
    public var changed: StandardEditLimit
    public var inserted: StandardEditLimit
    public var deleted: StandardEditLimit
    public var span: StandardEditLimit

    public init(
        operations: StandardEditLimit = .unlimited,
        changed: StandardEditLimit = .unlimited,
        inserted: StandardEditLimit = .unlimited,
        deleted: StandardEditLimit = .unlimited,
        span: StandardEditLimit = .unlimited
    ) {
        self.operations = operations
        self.changed = changed
        self.inserted = inserted
        self.deleted = deleted
        self.span = span
    }

    public static let unlimited = Self()

    public static let small = Self(
        operations: .limited(4),
        changed: .limited(18),
        inserted: .limited(12),
        deleted: .limited(8),
        span: .limited(8)
    )

    public static let medium = Self(
        operations: .limited(8),
        changed: .limited(48),
        inserted: .limited(32),
        deleted: .limited(24),
        span: .limited(24)
    )
}

public enum StandardEditScope: Sendable, Codable, Hashable, CustomStringConvertible {
    case file
    case lines([LineRange])
    case insertions([Int])

    public var description: String {
        switch self {
        case .file:
            return "file"

        case .lines(let ranges):
            let rendered = ranges.map { range in
                "\(range.start)...\(range.end)"
            }.joined(
                separator: ","
            )

            return "lines(\(rendered))"

        case .insertions(let positions):
            let rendered = positions
                .map(String.init)
                .joined(
                    separator: ","
                )

            return "insertions(\(rendered))"
        }
    }
}

public enum StandardEditOperationKind: String, Sendable, Codable, Hashable, CaseIterable {
    case replace_entire_file
    case append
    case prepend
    case replace_first
    case replace_all
    case replace_unique
    case replace_line
    case replace_line_guarded
    case insert_lines
    case insert_lines_guarded
    case replace_lines
    case replace_lines_guarded
    case delete_lines
    case delete_lines_guarded
}

public struct StandardEditOperationSet: Sendable, Codable, Hashable {
    public var allowed: Set<StandardEditOperationKind>

    public init(
        _ allowed: Set<StandardEditOperationKind>
    ) {
        self.allowed = allowed
    }

    public func allows(
        _ operation: StandardEditOperationKind
    ) -> Bool {
        allowed.contains(
            operation
        )
    }

    public static let all = Self(
        Set(
            StandardEditOperationKind.allCases
        )
    )

    public static let precise = Self(
        [
            .replace_line,
            .replace_line_guarded,
            .insert_lines,
            .insert_lines_guarded,
            .replace_lines,
            .replace_lines_guarded,
            .delete_lines,
            .delete_lines_guarded,
        ]
    )

    public static let guarded = Self(
        [
            .replace_line_guarded,
            .insert_lines_guarded,
            .replace_lines_guarded,
            .delete_lines_guarded,
        ]
    )

    public static let text = Self(
        [
            .replace_first,
            .replace_unique,
        ]
    )
}

public enum StandardEditGuardRequirement: String, Sendable, Codable, Hashable, CaseIterable {
    case optional
    case required
}

public enum StandardEditUnguardablePolicy: String, Sendable, Codable, Hashable, CaseIterable {
    case allow
    case deny
}

public struct StandardEditGuardPolicy: Sendable, Codable, Hashable {
    public var existingLines: StandardEditGuardRequirement
    public var insertions: StandardEditGuardRequirement
    public var unguardable: StandardEditUnguardablePolicy

    public init(
        existingLines: StandardEditGuardRequirement = .optional,
        insertions: StandardEditGuardRequirement = .optional,
        unguardable: StandardEditUnguardablePolicy = .allow
    ) {
        self.existingLines = existingLines
        self.insertions = insertions
        self.unguardable = unguardable
    }

    public static let none = Self()

    public static let guarded = Self(
        existingLines: .required,
        insertions: .required,
        unguardable: .deny
    )

    public static let existingLines = Self(
        existingLines: .required,
        insertions: .optional,
        unguardable: .deny
    )
}

public struct StandardEditConstraint: Sendable, Codable, Hashable {
    public var scope: StandardEditScope
    public var budget: StandardEditBudget
    public var operations: StandardEditOperationSet
    public var guards: StandardEditGuardPolicy

    public init(
        scope: StandardEditScope = .file,
        budget: StandardEditBudget = .unlimited,
        operations: StandardEditOperationSet = .all,
        guards: StandardEditGuardPolicy = .none
    ) {
        self.scope = scope
        self.budget = budget
        self.operations = operations
        self.guards = guards
    }

    public static let unrestricted = Self()

    public static let small = Self(
        budget: .small
    )

    public static let presets = StandardEditConstraintPresets()

    public static func bounded(
        scope: StandardEditScope,
        budget: StandardEditBudget = .small,
        operations: StandardEditOperationSet = .precise,
        guards: StandardEditGuardPolicy = .guarded
    ) -> Self {
        .init(
            scope: scope,
            budget: budget,
            operations: operations,
            guards: guards
        )
    }
}

public struct StandardEditConstraintPresets: Sendable {
    public init() {}

    public func small(
        scope: StandardEditScope = .file
    ) -> StandardEditConstraint {
        .init(
            scope: scope,
            budget: .small
        )
    }

    public func smallGuarded(
        scope: StandardEditScope
    ) -> StandardEditConstraint {
        .init(
            scope: scope,
            budget: .small,
            operations: .precise,
            guards: .guarded
        )
    }

    public func mediumGuarded(
        scope: StandardEditScope
    ) -> StandardEditConstraint {
        .init(
            scope: scope,
            budget: .medium,
            operations: .precise,
            guards: .guarded
        )
    }
}

public extension StandardEditOperation {
    var kind: StandardEditOperationKind {
        switch self {
        case .replaceEntireFile:
            return .replace_entire_file

        case .append:
            return .append

        case .prepend:
            return .prepend

        case .replaceFirst:
            return .replace_first

        case .replaceAll:
            return .replace_all

        case .replaceUnique:
            return .replace_unique

        case .replaceLine:
            return .replace_line

        case .replaceLineGuarded:
            return .replace_line_guarded

        case .insertLines:
            return .insert_lines

        case .insertLinesGuarded:
            return .insert_lines_guarded

        case .replaceLines:
            return .replace_lines

        case .replaceLinesGuarded:
            return .replace_lines_guarded

        case .deleteLines:
            return .delete_lines

        case .deleteLinesGuarded:
            return .delete_lines_guarded
        }
    }

    var hasExistingLineGuard: Bool {
        switch self {
        case .replaceLineGuarded,
             .replaceLinesGuarded,
             .deleteLinesGuarded:
            return true

        case .replaceEntireFile,
             .append,
             .prepend,
             .replaceFirst,
             .replaceAll,
             .replaceUnique,
             .replaceLine,
             .insertLines,
             .insertLinesGuarded,
             .replaceLines,
             .deleteLines:
            return false
        }
    }

    var hasInsertionGuard: Bool {
        switch self {
        case .insertLinesGuarded(_, _, let site):
            return site.hasContext

        case .replaceEntireFile,
             .append,
             .prepend,
             .replaceFirst,
             .replaceAll,
             .replaceUnique,
             .replaceLine,
             .replaceLineGuarded,
             .insertLines,
             .replaceLines,
             .replaceLinesGuarded,
             .deleteLines,
             .deleteLinesGuarded:
            return false
        }
    }

    var touchesExistingLines: Bool {
        switch self {
        case .replaceLine,
             .replaceLineGuarded,
             .replaceLines,
             .replaceLinesGuarded,
             .deleteLines,
             .deleteLinesGuarded:
            return true

        case .replaceEntireFile,
             .append,
             .prepend,
             .replaceFirst,
             .replaceAll,
             .replaceUnique,
             .insertLines,
             .insertLinesGuarded:
            return false
        }
    }

    var isInsertion: Bool {
        switch self {
        case .insertLines,
             .insertLinesGuarded:
            return true

        case .replaceEntireFile,
             .append,
             .prepend,
             .replaceFirst,
             .replaceAll,
             .replaceUnique,
             .replaceLine,
             .replaceLineGuarded,
             .replaceLines,
             .replaceLinesGuarded,
             .deleteLines,
             .deleteLinesGuarded:
            return false
        }
    }

    var isUnguardable: Bool {
        switch self {
        case .replaceEntireFile,
             .append,
             .prepend,
             .replaceFirst,
             .replaceAll,
             .replaceUnique:
            return true

        case .replaceLine,
             .replaceLineGuarded,
             .insertLines,
             .insertLinesGuarded,
             .replaceLines,
             .replaceLinesGuarded,
             .deleteLines,
             .deleteLinesGuarded:
            return false
        }
    }
}
