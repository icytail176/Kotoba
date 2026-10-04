# Kotoba Windows Client

Status: Early development prototype (Phase 0).

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

Windows CI/build verification will be added in Phase 1.

## Validation

```sh
npm run check
npm run build
cd src-tauri
cargo fmt --check
cargo check
cargo clippy -- -D warnings
```

Commit `package-lock.json` and `src-tauri/Cargo.lock` for reproducible dependency resolution. Generated output and local dependencies are ignored.

This phase contains no vocabulary, SQLite, SRS, or sync implementation. All client files are isolated under `windows/`; the existing macOS application is unchanged.
