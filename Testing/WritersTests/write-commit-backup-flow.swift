import Foundation
import Testing
import Writers

extension WritersFlowSuite {
    static var symlinkWriteThroughFlow: TestFlow {
        TestFlow(
            "symlink-write-through",
            tags: ["write", "symlink", "atomic"]
        ) {
            Step("atomic overwrite keeps the link and writes its target") {
                let workspace = try TestWorkspace("symlink-atomic")
                defer {
                    workspace.remove()
                }

                let real = workspace.file(
                    "real.txt"
                )
                let link = try workspace.symlink(
                    "link.txt",
                    to: "real.txt"
                )

                _ = try StandardWriter(
                    real
                ).write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                _ = try StandardWriter(
                    link
                ).write(
                    "after\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.equal(
                    try workspace.linkDestination(link),
                    "real.txt",
                    "symlink.atomic.link-kept"
                )
                try Expect.equal(
                    try workspace.read(real),
                    "after\n",
                    "symlink.atomic.target-content"
                )
            }

            Step("non-atomic overwrite keeps the link and writes its target") {
                let workspace = try TestWorkspace("symlink-non-atomic")
                defer {
                    workspace.remove()
                }

                let real = workspace.file(
                    "real.txt"
                )
                let link = try workspace.symlink(
                    "link.txt",
                    to: "real.txt"
                )
                var options = SafeWriteOptions.overwriteWithoutBackup
                options.atomic = false

                _ = try StandardWriter(
                    real
                ).write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                _ = try StandardWriter(
                    link
                ).write(
                    "after\n",
                    options: options
                )

                try Expect.equal(
                    try workspace.linkDestination(link),
                    "real.txt",
                    "symlink.non-atomic.link-kept"
                )
                try Expect.equal(
                    try workspace.read(real),
                    "after\n",
                    "symlink.non-atomic.target-content"
                )
            }

            Step("creation through a dangling link creates its target") {
                let workspace = try TestWorkspace("symlink-dangling")
                defer {
                    workspace.remove()
                }

                let real = workspace.file(
                    "missing.txt"
                )
                let link = try workspace.symlink(
                    "link.txt",
                    to: "missing.txt"
                )

                _ = try StandardWriter(
                    link
                ).write(
                    "created\n",
                    options: .overwriteWithoutBackup
                )

                try Expect.equal(
                    try workspace.linkDestination(link),
                    "missing.txt",
                    "symlink.dangling.link-kept"
                )
                try Expect.equal(
                    try workspace.read(real),
                    "created\n",
                    "symlink.dangling.target-content"
                )
            }

            Step("sibling backup through a link holds the previous content") {
                let workspace = try TestWorkspace("symlink-backup")
                defer {
                    workspace.remove()
                }

                let real = workspace.file(
                    "real.txt"
                )
                let link = try workspace.symlink(
                    "link.txt",
                    to: "real.txt"
                )

                _ = try StandardWriter(
                    real
                ).write(
                    "before\n",
                    options: .overwriteWithoutBackup
                )

                let result = try StandardWriter(
                    link
                ).write(
                    "after\n",
                    options: .overwriting(
                        backupPolicy: .sibling_file
                    )
                )

                let backupURL = try Expect.notNil(
                    result.backupRecord?.storage?.localURL,
                    "symlink.backup.url"
                )

                try Expect.equal(
                    try workspace.read(backupURL),
                    "before\n",
                    "symlink.backup.content"
                )
                try Expect.equal(
                    try workspace.read(real),
                    "after\n",
                    "symlink.backup.target-content"
                )
            }
        }
    }

    static var backupNamingFlow: TestFlow {
        TestFlow(
            "backup-naming",
            tags: ["backup", "naming"]
        ) {
            Step("repeated sibling backups never overwrite each other") {
                let workspace = try TestWorkspace("backup-naming-sibling")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let versions = (1...5).map {
                    "version \($0)\n"
                }

                _ = try writer.write(
                    versions[0],
                    options: .overwriteWithoutBackup
                )

                var backups: [URL] = []

                for version in versions.dropFirst() {
                    let result = try writer.write(
                        version,
                        options: .overwriting(
                            backupPolicy: .sibling_file
                        )
                    )

                    backups.append(
                        try Expect.notNil(
                            result.backupRecord?.storage?.localURL,
                            "backup.naming.sibling.url"
                        )
                    )
                }

                try Expect.equal(
                    Set(backups.map(\.lastPathComponent)).count,
                    backups.count,
                    "backup.naming.sibling.distinct"
                )
                try Expect.equal(
                    backups.first?.lastPathComponent,
                    "sample.txt_previous_version.bak",
                    "backup.naming.sibling.first-is-base"
                )
                try Expect.equal(
                    try backups.map {
                        try workspace.read($0)
                    },
                    Array(versions.dropLast()),
                    "backup.naming.sibling.contents"
                )
            }

            Step("without timestamps the base sibling backup is replaced") {
                let workspace = try TestWorkspace("backup-naming-replace")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                var options = SafeWriteOptions.overwriting(
                    backupPolicy: .sibling_file
                )
                options.addTimestampIfBackupExists = false

                _ = try writer.write(
                    "one\n",
                    options: .overwriteWithoutBackup
                )
                _ = try writer.write(
                    "two\n",
                    options: options
                )

                let result = try writer.write(
                    "three\n",
                    options: options
                )

                let backupURL = try Expect.notNil(
                    result.backupRecord?.storage?.localURL,
                    "backup.naming.replace.url"
                )

                try Expect.equal(
                    backupURL.lastPathComponent,
                    "sample.txt_previous_version.bak",
                    "backup.naming.replace.name"
                )
                try Expect.equal(
                    try workspace.read(backupURL),
                    "two\n",
                    "backup.naming.replace.content"
                )
                try Expect.equal(
                    try workspace.names(in: workspace.root)
                        .filter {
                            $0.hasSuffix(".bak")
                        }
                        .count,
                    1,
                    "backup.naming.replace.count"
                )
            }

            Step("repeated backup sets never overwrite each other") {
                let workspace = try TestWorkspace("backup-naming-sets")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let options = SafeWriteOptions.overwriting(
                    backupPolicy: .backup_directory,
                    maxBackupSets: nil
                )
                let versions = (1...5).map {
                    "version \($0)\n"
                }

                _ = try writer.write(
                    versions[0],
                    options: .overwriteWithoutBackup
                )

                var backups: [URL] = []

                for version in versions.dropFirst() {
                    let result = try writer.write(
                        version,
                        options: options
                    )

                    backups.append(
                        try Expect.notNil(
                            result.backupRecord?.storage?.localURL,
                            "backup.naming.sets.url"
                        )
                    )
                }

                let sets = backups.map {
                    $0.deletingLastPathComponent().lastPathComponent
                }

                try Expect.equal(
                    Set(sets).count,
                    sets.count,
                    "backup.naming.sets.distinct"
                )
                try Expect.equal(
                    sets,
                    sets.sorted(),
                    "backup.naming.sets.chronological"
                )
                try Expect.equal(
                    try backups.map {
                        try workspace.read($0)
                    },
                    Array(versions.dropLast()),
                    "backup.naming.sets.contents"
                )
            }
        }
    }

    static var backupKeepZeroFlow: TestFlow {
        TestFlow(
            "backup-keep-zero",
            tags: ["backup", "retention"]
        ) {
            Step("keep zero preserves the set an overwrite just made") {
                let workspace = try TestWorkspace("backup-keep-zero")
                defer {
                    workspace.remove()
                }

                let url = workspace.file(
                    "sample.txt"
                )
                let writer = StandardWriter(
                    url
                )
                let options = SafeWriteOptions.overwriting(
                    backupPolicy: .backup_directory,
                    maxBackupSets: 0
                )

                _ = try writer.write(
                    "one\n",
                    options: .overwriteWithoutBackup
                )

                for (previous, next) in [
                    ("one\n", "two\n"),
                    ("two\n", "three\n"),
                ] {
                    let result = try writer.write(
                        next,
                        options: options
                    )

                    let backupURL = try Expect.notNil(
                        result.backupRecord?.storage?.localURL,
                        "backup.keep-zero.url"
                    )

                    try Expect.equal(
                        try workspace.read(backupURL),
                        previous,
                        "backup.keep-zero.content"
                    )
                    try Expect.equal(
                        try workspace.names(
                            in: writer.backupBaseDir(
                                options: options
                            )
                        ),
                        [
                            backupURL.deletingLastPathComponent().lastPathComponent,
                        ],
                        "backup.keep-zero.only-current-set"
                    )
                }
            }

            Step("keep zero without a preserved set removes every matching set") {
                let workspace = try TestWorkspace("backup-keep-zero-direct")
                defer {
                    workspace.remove()
                }

                let writer = StandardWriter(
                    workspace.file(
                        "sample.txt"
                    )
                )
                let options = SafeWriteOptions.overwriting(
                    backupPolicy: .backup_directory,
                    maxBackupSets: 0
                )
                let base = try workspace.directory(
                    options.backupDirectoryName
                )

                for name in [
                    "overwrite_001",
                    "overwrite_002",
                    "other_001",
                ] {
                    _ = try workspace.directory(
                        "\(options.backupDirectoryName)/\(name)"
                    )
                }

                try writer.pruneBackupSets(
                    baseDir: base,
                    prefix: options.backupSetPrefix,
                    keep: 0
                )

                try Expect.equal(
                    try workspace.names(in: base),
                    [
                        "other_001",
                    ],
                    "backup.keep-zero.direct.names"
                )
            }
        }
    }
}
