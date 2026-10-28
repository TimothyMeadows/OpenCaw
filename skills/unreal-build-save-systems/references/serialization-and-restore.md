# Serialization, migration and restore

Verify APIs against the project's installed Unreal headers. Official references below select 5.8 as a review baseline; storage semantics still depend on the actual platform and selected implementation.

## Value data and identity

Model the save as bounded value data with an explicit schema version and identity namespace. Persist entity/instance IDs, authored-definition IDs, transforms and gameplay values with clear ownership. Do not serialize actor pointers or a complete live UObject graph and expect it to reconstruct a streamed world. A stable entity ID must distinguish repeated Level Instances and reject duplicates.

Use a reflected `USaveGame` subclass or another explicitly selected format for the envelope. Understand the serializer actually in use: `UGameplayStatics::SaveGameToSlot` is not a promise to select only properties marked `SaveGame`. A custom archive using `ArIsSaveGame` has its own property filtering and object-reference policy. Review what is emitted, including accidental credentials, account identifiers or developer-only fields, rather than assuming a specifier provides privacy.

For custom envelopes, validate magic/type, bounded payload length, schema and integrity before decoding. A checksum detects accidental corruption; it is not authentication or anti-cheat. Avoid handing arbitrary, unbounded untrusted data to engine object creation. Test controlled malformed inputs through the supported decoder, and place stricter bounds/authentication at an actual trust boundary when needed.

## Migration and transactional restoration

Decode into temporary storage. Reject unsupported future versions before interpreting fields. Apply explicit version-to-version migrations, preserving older fixtures and recording semantic changes such as renamed items or coordinate-space updates. Validate required IDs, uniqueness, numeric ranges, cardinality and availability of referenced definitions. A missing optional cosmetic may have an explicit fallback; a missing required gameplay definition must not silently become another item.

Resolve authored definitions and required streamed worlds before restoration. Build a validated restore plan, then apply it at one game-thread boundary with events temporarily coordinated so observers cannot see half-restored state. Re-run derived calculations after base values are established. Publish completion only after the world is consistent. Define rollback/compensation for actor spawning or other non-reversible effects; calling a sequence of setters is not inherently transactional.

## Async ownership and storage durability

The engine's async load performs work across threads and returns through a completion delegate; capture only thread-safe copied payload and validated weak owners. Bind user, slot, world and request generation. If the user changes, a newer load wins, or the world ends, invalidate the prior generation and suppress its application. Do not claim cancellation of platform disk I/O when only the application step is cancelled.

Serialize conflicting user/slot operations; a callback must identify the operation it completes. Keep a snapshot alive until save completion and inspect its success result. Choose journaling/backup, write-then-verify, or an actual atomic-replace facility supported by the target platform. Document when the last-known-good version is replaced and how interrupted writes are recovered. Test quota/full-storage/permission errors on the real target; desktop files do not establish console/cloud behavior.

## Native fixture and acceptance

A minimal native fixture should serialize a reflected legacy `USaveGame` value with `SaveGameToMemory`, deserialize it using `LoadGameFromMemory`, migrate/validate into a candidate, and only then assign live state. Assert migrated identity/value fidelity, no live mutation for future version/invalid ranges/duplicate IDs, repeat restore idempotence and decoder rejection of a controlled invalid header. Add real platform asynchronous and persistence tests separately; this in-memory fixture cannot certify crash durability, async cancellation or full-world restore.

## Official references

- [Saving and loading](https://dev.epicgames.com/documentation/en-us/unreal-engine/saving-and-loading-your-game-in-unreal-engine?application_version=5.8)
- [USaveGame](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/USaveGame?application_version=5.8)
- [UGameplayStatics save/load APIs](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/UGameplayStatics?application_version=5.8)
- [AsyncLoadGameFromSlot thread ownership](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/UGameplayStatics/AsyncLoadGameFromSlot?application_version=5.8)
