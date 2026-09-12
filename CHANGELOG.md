# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0-alpha.1]
### Added
- Embedded in-memory engine: `SurrealClient(endpoint: "mem://")` now runs SurrealDB in-process, with no server, no network and no ports. The full typed CRUD, query-DSL, raw-query and transaction surface works against it. Built on [surrealdb.c](https://github.com/surrealdb/surrealdb.c)'s typed C API, pinned to commit `039481e0`.
- `SurrealEmbeddedOptions` and `EmbeddedTarget`, plus an `embeddedOptions:` parameter on `SurrealClient.init`.
- `SurrealDBSDK.version` and `SurrealDBSDK.embeddedNativeRevision`; nothing surfaced the SDK version before, and an embedded build has two versions worth reporting.
- `scripts/build-embedded.sh` to build the native library, and `scripts/test-embedded.sh` to run the embedded suite. Embedded support is opt-in: without `SURREALDB_EMBEDDED=1` the C targets are not in the package graph at all, so nothing changes for existing consumers.
- CI job exercising the embedded engine on every pull request.

### Changed
- **Source-breaking:** `SurrealClient.Engine` gains a `.embedded` case. Exhaustive `switch` statements over it will need a new arm.
- The four capability-gating messages for sessions and live queries named HTTP unconditionally, which was wrong on any other transport. They now name the engine in use, via a new defaulted `transportDescription` on the internal `RPCEngine` protocol.
- `SurrealError.invalidEndpoint`'s recovery suggestion now lists `mem://`.

### Fixed
- `integration_sessionForkIsolationAndClose` existed but was never run: `scripts/test-integration.sh` invokes an explicit list of tests and it was missing from it. The script now fails if any `integration_*` test is unlisted.
- CI never ran on tag pushes, and its release gate matched `refs/heads/v*` while the branch convention in use is `dev/v*`. Both now match.

### Known limitations
- Embedded requires a Rust toolchain to build the native library; there is no prebuilt artifact yet. Distributing one is not simply a matter of publishing it: the macOS + iOS XCFramework is 223 MB zipped, and SwiftPM resolves binary artifacts for the whole package graph, so a `binaryTarget` here would impose that download on everyone using the plain WebSocket client. A separate package is the likely answer. The build is verified for macOS (arm64, x86_64) and iOS (arm64 device, arm64 + x86_64 simulator). tvOS, watchOS and visionOS slices are wired up but unverified, since `aws-lc-sys`, pulled in unavoidably by `surrealdb-core`'s JWT support, only has CMake branches for iOS and tvOS.
- Live queries and multi-session are unavailable on `mem://` and throw `SurrealError.unsupportedFeature`. The C API exposes live queries only by table name, with no way to attach to the id that `LIVE SELECT` returns, so bridging them would silently drop the query's `WHERE` clause.
- `queryRaw` on `mem://` returns a scalar statement result wrapped in an array (`RETURN 1` yields `.array([.int(1)])` rather than `.int(1)`). `sr_query` destroys the distinction before Swift sees it. The typed APIs are unaffected, since they flatten arrays anyway.
- Values with no C representation (`.table`, `.range`, geometry collections, multi-ring polygons) throw rather than being silently coerced when bound. Values SurrealDB has but surrealdb.c does not model arrive as `NONE`; that loss happens inside the Rust layer.
- Per-statement error kinds are recovered heuristically from message text, because surrealdb.c discards the server's structured error. Unrecognised messages classify as `.internalError`.

## [1.0.0-alpha.2]
### Changed
- Renamed the Spectron client to Agent Memory: the library product and module `Spectron` is now `AgentMemory`, and the types it exports lose the `Spectron` prefix (`Spectron` → `AgentMemory`, `SpectronError` → `AgentMemoryError`, `SpectronTransport` → `AgentMemoryTransport`, and so on). Source-breaking for anyone on `v1.0.0-alpha.1`.

### Added
- Initial SurrealDB Swift client: core query builder, table/field modeller, transport protocol abstraction (HTTP/WebSocket), CBOR codec, and integration test harness.
- Engine and codec abstraction, plus the Agent Memory SDK.
- Typed `ServerErrorKind` enum taxonomy mirroring the server's `{code, message, kind, details, cause}` wire shape, with convenience booleans (`isTokenExpired`, `isInvalidAuth`, `isTransactionConflict`, `isNotFound`, `isAlreadyExists`, etc.) (#5).
- Multi-session support: one WebSocket connection can now multiplex multiple independent sessions (namespace/database/auth/bound variables), via `newSession()`/`forkSession()`/`closeSession()`/`sessions()`, mirroring `surrealdb.js`'s multi-session model. WebSocket only — HTTP throws `SurrealError.unsupportedFeature` (#6).
- `set()`/`unset()` on `SurrealQueryable` for client-side session-scoped bound variables (#6).
- Reconnect-replay mechanism restoring a session's namespace/database/auth after a WebSocket reconnect, fixing a pre-existing bug where that state was silently dropped (#6).

### Fixed
- `QueryErrorDetail` was silently dropping `kind` for per-statement query failures; it now carries `kind` and exposes `.typedKind` (#5).
- JSON wire codec was silently dropping the `session`/`txn` fields the CBOR codec already carried (#6).

[Unreleased]: https://github.com/surrealdb/surrealdb.swift/compare/v1.1.0-alpha.1...HEAD
[1.1.0-alpha.1]: https://github.com/surrealdb/surrealdb.swift/compare/v1.0.0-alpha.2...v1.1.0-alpha.1
[1.0.0-alpha.2]: https://github.com/surrealdb/surrealdb.swift/compare/v1.0.0-alpha.1...v1.0.0-alpha.2
[1.0.0-alpha.1]: https://github.com/surrealdb/surrealdb.swift/releases/tag/v1.0.0-alpha.1
