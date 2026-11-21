import Foundation
import IO

/// Planning-time check that a pass fits its destination volumes: no file larger
/// than a volume holds (FAT32: 4 GiB − 1), and no volume asked for more than it
/// has free. Only entries that write data count: copies, and moves between
/// volumes (a rename on one volume writes nothing).
///
/// Advisory: the disk can fill between planning and publishing. IO's copy then
/// fails with `FileSystemError(.copy)` and leaves no destination.
///
/// Cost, planning only: one `statfs` + `pathconf` per distinct destination
/// directory, one `statfs` per moved source, one `fts` walk per copied or
/// cross-volume source.
enum StandardMutationCapacity {
    static func require(
        _ entries: [StandardMutationEntry]
    ) throws {
        var volumes: [String: (url: URL, volume: FileSystem.Volume)] = [:]
        var needed: [UInt64: (url: URL, volume: FileSystem.Volume, bytes: Int64)] = [:]

        for entry in entries {
            let source: URL
            let destination: URL
            switch entry {
            case .copy(let copy):
                source = copy.source
                destination = copy.destination
            case .move(let move):
                source = move.source
                destination = move.destination
            case .create_text, .replace_text, .edit_text, .delete:
                continue
            }

            guard let target = destinationVolume(
                destination,
                cache: &volumes
            ) else {
                continue
            }

            if case .move = entry {
                guard let origin = try? FileSystem.default.volume(of: source),
                      origin.identifier != target.volume.identifier
                else {
                    continue
                }
            }

            guard let footprint = try? FileSystem.default.footprint(
                of: source,
                rounding: target.volume.blockSize
            ) else {
                continue
            }

            if let limit = target.volume.maxFileSize,
               footprint.largestFile > limit
            {
                throw StandardMutationError.exceeds_file_size_limit(
                    source: source,
                    destination: destination,
                    size: footprint.largestFile,
                    limit: limit
                )
            }

            let previous = needed[target.volume.identifier]?.bytes ?? 0
            needed[target.volume.identifier] = (
                target.url,
                target.volume,
                previous + footprint.allocated
            )
        }

        for (_, demand) in needed.sorted(by: { $0.key < $1.key })
        where demand.bytes > demand.volume.available {
            throw StandardMutationError.insufficient_space(
                volume: demand.url,
                needed: demand.bytes,
                available: demand.volume.available
            )
        }
    }

    /// The volume a destination lands on: that of its nearest existing
    /// ancestor, since missing parents may be created by the entry.
    private static func destinationVolume(
        _ destination: URL,
        cache: inout [String: (url: URL, volume: FileSystem.Volume)]
    ) -> (url: URL, volume: FileSystem.Volume)? {
        var directory = destination.standardizedFileURL.deletingLastPathComponent()
        while !FileSystem.default.exists(directory) {
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else {
                return nil
            }
            directory = parent
        }
        if let cached = cache[directory.path] {
            return cached
        }
        guard let volume = try? FileSystem.default.volume(of: directory) else {
            return nil
        }
        let found = (url: directory, volume: volume)
        cache[directory.path] = found
        return found
    }
}
