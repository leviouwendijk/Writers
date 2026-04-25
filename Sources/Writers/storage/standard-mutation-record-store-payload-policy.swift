import Foundation

public extension StandardMutationRecordStore {
    @discardableResult
    func store(
        _ record: WriteMutationRecord,
        payloadPolicy: WriteMutationPayloadPolicy
    ) throws -> WriteStoredRecord {
        switch payloadPolicy {
        case .inline:
            return try store(
                record.withPayloadPolicyMetadata(
                    payloadPolicy
                )
            )

        case .external_content:
            let payload = try payloads.store(
                record,
                policy: payloadPolicy
            )
            let manifest = try payloads.storeManifest(
                payload
            )
            let stripped = record
                .withoutInlinePayloadContent()
                .withPayloadMetadata(
                    payload,
                    manifest: manifest
                )

            return try store(
                stripped
            )

        case .metadata_only:
            return try store(
                record
                    .withoutInlinePayloadContent()
                    .withPayloadPolicyMetadata(
                        payloadPolicy
                    )
            )
        }
    }
}

public extension WriteMutationRecord {
    func withoutInlinePayloadContent() -> Self {
        .init(
            id: id,
            target: target,
            createdAt: createdAt,
            operationKind: operationKind,
            before: before?.withoutContent(),
            after: after?.withoutContent(),
            difference: difference,
            backupRecord: backupRecord,
            writeResult: writeResult,
            rollbackOperations: rollbackOperations,
            rollbackGuard: rollbackGuard,
            metadata: metadata
        )
    }

    func withPayloadPolicyMetadata(
        _ policy: WriteMutationPayloadPolicy
    ) -> Self {
        var next = WriteMutationMetadata(
            raw: metadata
        )
        next.raw[
            WriteMutationPayloadMetadataKey.payload_policy
        ] = policy.rawValue

        return withMetadata(
            next
        )
    }

    func withPayloadMetadata(
        _ payload: WriteMutationPayloadRecord,
        manifest: WriteStorageLocation?
    ) -> Self {
        var next = WriteMutationMetadata(
            raw: metadata
        )

        next.raw[
            WriteMutationPayloadMetadataKey.payload_policy
        ] = payload.policy.rawValue
        next.raw[
            WriteMutationPayloadMetadataKey.payload_manifest
        ] = manifest?.value
        next.raw[
            WriteMutationPayloadMetadataKey.payload_before
        ] = payload.before?.value
        next.raw[
            WriteMutationPayloadMetadataKey.payload_after
        ] = payload.after?.value
        next.raw[
            WriteMutationPayloadMetadataKey.payload_diff
        ] = payload.diff?.value
        next.raw[
            WriteMutationPayloadMetadataKey.payload_rollback
        ] = payload.rollback?.value

        return withMetadata(
            next
        )
    }
}

public extension WriteMutationSnapshot {
    func withoutContent() -> Self {
        .init(
            fingerprint: fingerprint,
            byteCount: byteCount,
            lineCount: lineCount,
            content: nil
        )
    }
}

public extension StandardMutationRecordStore.Payloads {
    func storeManifest(
        _ payload: WriteMutationPayloadRecord
    ) throws -> WriteStorageLocation {
        let url = manifestURL(
            mutationID: payload.mutationID
        )

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
        ]

        let data = try encoder.encode(
            payload
        )

        try data.write(
            to: url,
            options: .atomic
        )

        return .local(
            url
        )
    }

    func manifestURL(
        mutationID: UUID
    ) -> URL {
        directoryURL
            .appendingPathComponent(
                mutationID.uuidString.lowercased(),
                isDirectory: true
            )
            .appendingPathComponent(
                "payload-manifest.json",
                isDirectory: false
            )
    }
}
