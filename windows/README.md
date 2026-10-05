# Kotoba Windows Client

Status: Data foundation prototype (Phase 3).

Technology: Tauri 2, Svelte, TypeScript, Rust. The official Svelte template uses SvelteKit with a static adapter and Vite.

## Development on macOS

Prerequisites: Node.js/npm, Rust/Cargo, and Xcode command line tools.

```sh
cd windows
npm install
npm run tauri dev
```

The placeholder displays Japanese text and calls the side-effect-free Rust `app_info` command once when mounted. `IPC connected` and the returned platform confirm the IPC path.

Running `tauri dev` on macOS verifies the shared Tauri application stack,
but does not constitute Windows platform validation.

Windows CI validates frontend checks, Rust checks/tests, and native MSI/NSIS/EXE builds. See the phase reports for specific run evidence.

## Validation

```sh
npm run check
npm run build
cd src-tauri
cargo fmt --check
cargo check
cargo clippy -- -D warnings
cargo test --locked
```

Commit `package-lock.json` and `src-tauri/Cargo.lock` for reproducible dependency resolution. Generated output and local dependencies are ignored.

SQLite Schema 2 is initialized through Rust in Tauri's OS app-data directory as `kotoba.sqlite3`, using bundled SQLite. The placeholder calls typed `database_info` and displays `Database connected` / `Schema 2`; it cannot execute arbitrary SQL. Tests use only in-memory or temporary file databases.

Five canonical built-in books and 10,609 words are imported by Rust from a compile-time embedded shared manifest. Local UUIDs remain separate from canonical UUID v5 identities. Startup import is transactional and idempotent; user favorites, archive state, progress and logs are preserved. The diagnostic page shows counts and literal substring search (bounded results). No SRS or sync is implemented.

Canonical identity is **READY** and Windows mapping is implemented; Mac canonical mapping is **NOT IMPLEMENTED**. See [shared identity rules](../shared/vocabulary/README.md), [the data contract](docs/CROSS_PLATFORM_DATA_CONTRACT.md), and [Phase 3 report](PHASE_3_REPORT.md).

```sh
python3 tools/vocabulary_manifest.py validate
python3 -m unittest discover -s tools -p 'test_*.py'
```

The historical Schema 1 definition is unchanged; migration 2 adds canonical fields and independent content metadata. CI validates manifest/source drift, immutable ledger reservations, tests and the actual release executable's embedded resource from an empty directory.

Client code remains under `windows/`, shared vocabulary under `shared/vocabulary/`, and validation is added to Windows CI. Existing macOS source/resources/scripts are unchanged.
