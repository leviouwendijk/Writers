import Foundation
import Writers

private struct Measurement {
    let milliseconds: Double
    let observation: Int
}

private typealias Scenario = (
    label: String,
    sample: () throws -> Measurement
)

@main
enum WritersBenchmarkMain {
    static func main() throws {
        let samples = max(
            1,
            Int(ProcessInfo.processInfo.environment["WRITERS_BENCH_SAMPLES"] ?? "") ?? 3
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "writers-benchmark-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: root
            )
        }

        print(
            "size_bytes\tsize_mib\tscenario\tsamples\tmedian_ms\tmin_ms\tmax_ms\tmib_per_s\tobservation"
        )

        for size in [
            512 * 1024,
            5 * 1024 * 1024,
            50 * 1024 * 1024,
        ] {
            try benchmark(
                size: size,
                samples: samples,
                root: root
            )
        }
    }
}

private extension WritersBenchmarkMain {
    static func benchmark(
        size: Int,
        samples: Int,
        root: URL
    ) throws {
        let oldData = Data(
            repeating: 0x61,
            count: size
        )

        let newString = String(
            repeating: "b",
            count: size
        )

        let newData = Data(
            newString.utf8
        )

        precondition(
            oldData.count == size
        )

        precondition(
            newData.count == size
        )

        let knownFingerprint =
            StandardContentFingerprint
            .fingerprint(
                for: newData
            )

        let target = root.appendingPathComponent(
            "payload-\(size).txt",
            isDirectory: false
        )

        let writer = StandardWriter(
            target
        )

        let strict =
            SafeWriteOptions
            .overwriteWithoutBackup

        var allowDrift =
            SafeWriteOptions
            .overwriteWithoutBackup

        allowDrift.stalePlanPolicy =
            .allow_drift

        func prime() throws {
            try oldData.write(
                to: target,
                options: []
            )
        }

        func conflict() -> SafeFileOverwriteConflict {
            .init(
                url: target,
                difference: nil
            )
        }

        let scenarios: [Scenario] = [
            (
                "string-to-data",
                {
                    measure {
                        observe(
                            Data(
                                newString.utf8
                            )
                        )
                    }
                }
            ),
            (
                "fingerprint-data",
                {
                    measure {
                        let fingerprint =
                            StandardContentFingerprint
                            .fingerprint(
                                for: newData
                            )

                        return fingerprint
                            .value
                            .utf8
                            .reduce(
                                0
                            ) {
                                $0 &+ Int(
                                    $1
                                )
                            }
                    }
                }
            ),
            (
                "utf8-decode-data",
                {
                    measure {
                        guard let decoded = String(
                            data: newData,
                            encoding: .utf8
                        ) else {
                            return -1
                        }

                        return observe(
                            decoded
                        )
                    }
                }
            ),
            (
                "snapshot-data-known-fingerprint",
                {
                    measure {
                        observe(
                            WriteMutationSnapshot(
                                data: newData,
                                fingerprint: knownFingerprint
                            )
                        )
                    }
                }
            ),
            (
                "snapshot-data-known-fingerprint-with-content",
                {
                    measure {
                        observe(
                            WriteMutationSnapshot(
                                data: newData,
                                fingerprint: knownFingerprint,
                                content: newString
                            )
                        )
                    }
                }
            ),
            (
                "snapshot-string-full",
                {
                    measure {
                        observe(
                            WriteMutationSnapshot(
                                content: newString
                            )
                        )
                    }
                }
            ),
            (
                "foundation-read-uncached",
                {
                    try prime()

                    return try measure {
                        observe(
                            try Data(
                                contentsOf: target,
                                options: .uncached
                            )
                        )
                    }
                }
            ),
            (
                "foundation-write-nonatomic",
                {
                    try prime()

                    return try measure {
                        try newData.write(
                            to: target,
                            options: []
                        )

                        return newData.count
                    }
                }
            ),
            (
                "foundation-write-atomic",
                {
                    try prime()

                    return try measure {
                        try newData.write(
                            to: target,
                            options: .atomic
                        )

                        return newData.count
                    }
                }
            ),
            (
                "writer-plan-data-existing",
                {
                    try prime()

                    return try measure {
                        observe(
                            try writer.preflight.data(
                                newData,
                                options: strict
                            )
                        )
                    }
                }
            ),
            (
                "writer-plan-string-existing",
                {
                    try prime()

                    return try measure {
                        observe(
                            try writer.preflight.string(
                                newString,
                                options: strict
                            )
                        )
                    }
                }
            ),
            (
                "writer-execute-prepared-strict",
                {
                    try prime()

                    let plan = try writer.preflight.data(
                        newData,
                        options: strict
                    )

                    return try measure {
                        observe(
                            try plan.execution.apply(
                                writer: writer,
                                options: strict,
                                conflict: conflict()
                            )
                        )
                    }
                }
            ),
            (
                "writer-execute-prepared-allow-drift",
                {
                    try prime()

                    let plan = try writer.preflight.data(
                        newData,
                        options: allowDrift
                    )

                    return try measure {
                        observe(
                            try plan.execution.apply(
                                writer: writer,
                                options: allowDrift,
                                conflict: conflict()
                            )
                        )
                    }
                }
            ),
            (
                "writer-full-string-strict",
                {
                    try prime()

                    return try measure {
                        observe(
                            try writer.write(
                                newString,
                                options: strict
                            )
                        )
                    }
                }
            ),
            (
                "writer-full-string-allow-drift",
                {
                    try prime()

                    return try measure {
                        observe(
                            try writer.write(
                                newString,
                                options: allowDrift
                            )
                        )
                    }
                }
            ),
        ]

        for scenario in scenarios {
            var measurements: [Measurement] = []

            measurements.reserveCapacity(
                samples
            )

            for _ in 0..<samples {
                measurements.append(
                    try scenario.sample()
                )
            }

            printResult(
                size: size,
                label: scenario.label,
                measurements: measurements
            )
        }
    }

    static func measure(
        _ operation: () throws -> Int
    ) rethrows -> Measurement {
        let clock = ContinuousClock()
        let start = clock.now
        let observation = try operation()
        let duration = start.duration(
            to: clock.now
        )

        let components =
            duration.components

        let milliseconds =
            Double(
                components.seconds
            ) * 1_000
            + Double(
                components.attoseconds
            ) / 1_000_000_000_000_000

        return .init(
            milliseconds: milliseconds,
            observation: observation
        )
    }

    static func printResult(
        size: Int,
        label: String,
        measurements: [Measurement]
    ) {
        let sorted = measurements
            .map(
                \.milliseconds
            )
            .sorted()

        let median =
            median(
                sorted
            )

        let mib =
            Double(size)
            / 1_048_576

        let mibPerSecond =
            median > 0
            ? mib / (median / 1_000)
            : 0

        let observation =
            measurements
            .reduce(
                0
            ) {
                $0 &+ $1.observation
            }

        print(
            [
                String(
                    size
                ),
                format(
                    mib
                ),
                label,
                String(
                    measurements.count
                ),
                format(
                    median
                ),
                format(
                    sorted.first ?? 0
                ),
                format(
                    sorted.last ?? 0
                ),
                format(
                    mibPerSecond
                ),
                String(
                    observation
                ),
            ].joined(
                separator: "\t"
            )
        )
    }

    static func median(
        _ sorted: [Double]
    ) -> Double {
        let midpoint =
            sorted.count / 2

        guard sorted.count.isMultiple(
            of: 2
        ) else {
            return sorted[
                midpoint
            ]
        }

        return (
            sorted[
                midpoint - 1
            ]
            + sorted[
                midpoint
            ]
        ) / 2
    }

    static func format(
        _ value: Double
    ) -> String {
        String(
            format: "%.3f",
            value
        )
    }

    @inline(never)
    static func observe(
        _ text: String
    ) -> Int {
        let bytes = text.utf8

        return bytes.count
            &+ Int(
                bytes.first ?? 0
            )
            &+ Int(
                bytes.last ?? 0
            )
    }

    @inline(never)
    static func observe(
        _ snapshot: WriteMutationSnapshot
    ) -> Int {
        snapshot.byteCount
            &+ (snapshot.lineCount ?? 0)
            &+ snapshot.fingerprint.value.utf8.count
            &+ (snapshot.content?.utf8.count ?? 0)
    }

    @inline(never)
    static func observe(
        _ data: Data
    ) -> Int {
        data.count
            &+ Int(
                data.first ?? 0
            )
            &+ Int(
                data.last ?? 0
            )
    }

    @inline(never)
    static func observe(
        _ plan: WritePlan
    ) -> Int {
        plan.incoming.data.count
            &+ (plan.before?.byteCount ?? 0)
            &+ plan.after.byteCount
            &+ (plan.canProceed ? 1 : 0)
    }

    @inline(never)
    static func observe(
        _ result: SafeWriteResult
    ) -> Int {
        result.bytesWritten
            &+ (result.wrote ? 1 : 0)
            &+ (result.overwrittenExisting ? 1 : 0)
    }
}
