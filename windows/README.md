# Kotoba Windows Client

Status: Data foundation prototype (Phase 2).

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

SQLite Schema 1 is initialized through Rust in Tauri's OS app-data directory as `kotoba.sqlite3`, using bundled SQLite. The placeholder calls typed `database_info` and displays `Database connected` / `Schema 1`; it cannot execute arbitrary SQL. Tests use only in-memory or temporary file databases.

No built-in vocabulary, import, SRS, or sync is implemented. Built-in cross-platform IDs are **NOT READY**: existing Mac seeds use random UUIDs. A shared identity design must be selected before real vocabulary import. See [the data contract](docs/CROSS_PLATFORM_DATA_CONTRACT.md) and [Phase 2 report](PHASE_2_REPORT.md).

Client files remain isolated under `windows/`, with only the Rust test step added to the existing Windows workflow; the existing macOS application is unchanged.
