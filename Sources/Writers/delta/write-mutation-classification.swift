
public extension WriteMutationDifferenceSummary {
    var deltaKind: WriteDeltaKind {
        if !hasChanges {
            return .unchanged
        }

        if insertions > 0,
           deletions > 0 {
            return .replacement
        }

        if insertions > 0 {
            return .addition
        }

        if deletions > 0 {
            return .deletion
        }

        return .unknown
    }
}

public extension StandardEditChangeKind {
    var deltaKind: WriteDeltaKind {
        switch self {
        case .insertion:
            return .addition

        case .deletion:
            return .deletion

        case .replacement:
            return .replacement
        }
    }
}

public extension StandardEditChange {
    var deltaKind: WriteDeltaKind {
        kind.deltaKind
    }
}

public extension WriteMutationRecord {
    var resourceChangeKind: WriteResourceChangeKind {
        switch (
            before == nil,
            after == nil
        ) {
        case (true, false):
            return .creation

        case (false, true):
            return .deletion

        case (false, false):
            return .update

        case (true, true):
            return .unknown
        }
    }

    var deltaKind: WriteDeltaKind {
        if let difference {
            return difference.deltaKind
        }

        if before == nil,
           after != nil {
            return .addition
        }

        if before != nil,
           after == nil {
            return .deletion
        }

        if before?.fingerprint == after?.fingerprint {
            return .unchanged
        }

        if before != nil,
           after != nil {
            return .replacement
        }

        return .unknown
    }
}
