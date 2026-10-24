import Difference
import Foundation
import Path

/// The affected-path projection of a prepared plan, not a scan or a complete
/// before/after filesystem inventory. The plan retains typed mutation intent.
public enum StandardMutationDifferenceError: Error, Sendable, Equatable {
    case path_outside_root(URL)
    case root_is_mutation_target(URL)
    case unrepresented_non_text_update(URL)
}

public extension StandardMutationPlan {
    /// Construct one typed difference from already-prepared operations.
    /// File contents are taken from the plan; no paths are read or mutated.
    /// A copy is an added destination; its source remains in both projections.
    /// A move uses its typed source/destination and a stable node identity.
    func difference(root: URL) throws -> Difference<PathTreeDifferenceValue> {
        let root = root.standardizedFileURL
        let root_path = StandardPath(rawPath: root.path)
        var before = PathTree(root: root_path)
        var after = PathTree(root: root_path)
        var relocated_ids: [String: String] = [:]
        var contents: [Difference<PathTreeDifferenceValue>.ContentChange] = []

        func identity(_ url: URL) -> String {
            StandardPath(rawPath: url.standardizedFileURL.path)
                .render(as: .relative, filetype: true)
        }

        func include(_ url: URL, directory: Bool, in tree: inout PathTree) throws {
            let url = url.standardizedFileURL
            let root_string = root.path
            let candidate = url.path
            let prefix = root_string == "/" ? "/" : root_string + "/"
            guard candidate == root_string || candidate.hasPrefix(prefix) else {
                throw StandardMutationDifferenceError.path_outside_root(url)
            }
            guard candidate != root_string else {
                throw StandardMutationDifferenceError.root_is_mutation_target(url)
            }
            if directory {
                try tree.appendDirectory(StandardPath(rawPath: candidate))
            } else {
                try tree.appendFile(StandardPath(rawPath: candidate))
            }
        }

        // Parent nodes are grouping scaffolds, not evidence that a directory
        // itself is being created/deleted. Keep them on both sides.
        for path in entries.flatMap({ $0.entry.targets }) {
            let candidate = path.standardizedFileURL
            let root_string = root.path
            let prefix = root_string == "/" ? "/" : root_string + "/"
            guard candidate.path.hasPrefix(prefix) else {
                throw StandardMutationDifferenceError.path_outside_root(candidate)
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path != root.path {
                try before.appendDirectory(StandardPath(rawPath: parent.path))
                try after.appendDirectory(StandardPath(rawPath: parent.path))
            }
        }

        for planned in entries {
            switch planned.entry {
            case .copy(let copy):
                let directory = planned.copyPlan?.source.kind == .directory
                try include(copy.source, directory: directory, in: &before)
                try include(copy.source, directory: directory, in: &after)
                try include(copy.destination, directory: directory, in: &after)

            case .move(let move):
                let directory = planned.movePlan?.source.kind == .directory
                try include(move.source, directory: directory, in: &before)
                try include(move.destination, directory: directory, in: &after)
                relocated_ids[identity(move.destination)] = identity(move.source)

            case .create_text, .replace_text, .edit_text, .delete:
                if planned.before.exists {
                    try include(planned.target, directory: false, in: &before)
                }
                if planned.after.exists {
                    try include(planned.target, directory: false, in: &after)
                }
                let before_text: String?
                let after_text: String?
                switch planned.before {
                case .missing: before_text = ""
                case .text(let value): before_text = value.content
                case .data: before_text = nil
                }
                switch planned.after {
                case .missing: after_text = ""
                case .text(let value): after_text = value.content
                case .data: after_text = nil
                }
                if before_text == nil || after_text == nil {
                    if planned.before.exists && planned.after.exists
                        && planned.delta != .unchanged {
                        throw StandardMutationDifferenceError.unrepresented_non_text_update(
                            planned.target
                        )
                    }
                }
                if (planned.before.exists || planned.after.exists),
                   let before_text, let after_text {
                    let node_id = identity(planned.target)
                    let path = identity(planned.target)
                    contents.append(.init(
                        id: planned.id.uuidString,
                        node_id: node_id,
                        difference: TextDiffer.diff(
                            old: before_text,
                            new: after_text,
                            oldName: "a/\(path)",
                            newName: "b/\(path)"
                        )
                    ))
                }
            }
        }

        let structure = try PathTree.difference(
            before: before,
            after: after,
            source: .planned,
            identity: { path in
                let id = path.render(as: .relative, filetype: true)
                return relocated_ids[id] ?? id
            }
        )
        return try Difference(structure: structure, contents: contents)
    }
}
