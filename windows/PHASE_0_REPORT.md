# Kotoba Windows Phase 0 Report

## Environment

- Node: 26.10.0
- npm: 11.19.1
- Rust: 1.99.0 (b940084d7 2026-09-28)
- Cargo: 1.99.0 (5f94df478 2026-08-27)
- Tauri: Rust runtime 2.12.1; CLI/API 2.12.1
- Svelte: 5.57.1 (SvelteKit 2.70.3)
- TypeScript: 6.0.3
- Vite: 8.3.2
- Official scaffolding tool: create-tauri-app 4.7.4, svelte-ts template, Tauri 2, npm

## Repository

- Branch: feature/windows-client
- Base commit: 21ea7c6b83dc18d9283f190c415e666f02463e83
- Initial working tree: clean on main
- Git add / commit / push: not performed

## Project Structure

```text
windows/
  package.json / package-lock.json
  tsconfig.json / vite.config.js / svelte.config.js
  src/app.html
  src/routes/+layout.ts / +page.svelte
  static/ (empty; unused template images removed)
  src-tauri/
    Cargo.toml / Cargo.lock / build.rs / tauri.conf.json
    capabilities/default.json
    src/lib.rs / main.rs
    icons/ (official template icons)
  README.md
  PHASE_0_REPORT.md
```

The current official Svelte template uses SvelteKit with adapter-static and outputs to build/. There are no additional product pages or shared/ directory.

## App Configuration

- Product name: Kotoba
- Window title / HTML title: Kotoba
- Identifier: com.fumi.kotoba.windows
- Frontend: Svelte + strict TypeScript, SvelteKit static SPA, Vite
- Backend: Rust + Tauri 2
- Window: 800 × 600 initially, resizable, minimum 320 × 360
- UTF-8 HTML; lang=ja; system fonts; light/dark appearance
- Permissions: core:default only; no opener plugin

The identifier follows Tauri's reverse-domain syntax and allowed characters. The existing macOS bundle identifier com.fumi.Kotoba remains unchanged.

Sources: [official project tooling](https://v2.tauri.app/start/create-project/), [identifier rules](https://v2.tauri.app/reference/config/#identifier).

## Validation

| Check | Result |
| --- | --- |
| npm install | PASS; lockfile generated |
| frontend check | PASS; 0 errors, 0 warnings |
| frontend build | PASS; static output in build/ |
| cargo fmt / cargo fmt --check | PASS |
| cargo check | PASS |
| cargo clippy -- -D warnings | PASS |
| tauri dev | PASS; development page, IPC, Japanese glyphs verified; normal exit code 0 |
| additional macOS debug app bundle | PASS; generated only for local UI verification |
| native window resizing | PASS; initial and native zoomed sizes, no horizontal overflow |

`npm run tauri dev` was run on macOS and successfully launched target/debug/kotoba-windows. The UI tool could not identify the unbundled process. An additional `npm run tauri build -- --debug --bundles app` generated an ignored local macOS debug app, whose placeholder, IPC return values, and Japanese glyphs were verified.

To verify the actual development pipeline as well, `tauri dev --runner <temporary runner>` was then run. The runner, created only under ignored src-tauri/target/, built the same Rust source without default features and launched that development binary from the generated .app wrapper, preserving its identity for UI inspection. The UI accessibility tree confirmed the development URL localhost:1420/, all placeholder text, and IPC connected / Kotoba · macos · Phase 0. A screenshot confirmed Japanese glyphs. Native zoom changed the window size and preserved the layout without horizontal overflow. The app was restored and quit with Cmd+Q; the Tauri dev process exited with code 0. The temporary runner was removed after verification.

No runner or application wrapper is needed for normal development; `npm run tauri dev` remains the documented command. These checks verify the shared macOS development stack, not Windows platform behavior.

## IPC Test

app_info: PASS. The running development window displayed IPC connected and Kotoba · macos · Phase 0.

The side-effect-free command serializes { name: "Kotoba", platform: std::env::consts::OS, phase: 0 }. A typed AppInfo interface and invoke<AppInfo>("app_info") call run once on mount. The page displays IPC connected and returned values, or an explicit error.

## Japanese Text Rendering

PASS. Screenshots of both the bundled static page and actual localhost:1420 development page showed 日本語 · ことば · 漢字 · カタカナ with correct glyphs. The initial and native zoomed windows showed no horizontal overflow. UTF-8 source, lang=ja, system fonts, and responsive wrapping are configured. The 320-pixel minimum-width layout was not separately inspected.

## macOS Project Isolation

All new repository files are under windows/. git diff --stat and git diff --name-only show no changes to tracked files. git status --short shows only ?? windows/. Existing Swift sources, schemas, Xcode project, resources, tests, root README, release/version metadata, and workflows are unchanged.

The existing empty directory was physically named Windows on the case-insensitive filesystem; its case was normalized to windows before final verification. No user files were replaced.

node_modules, build, dist, .svelte-kit, target, generated Tauri schemas, and local IDE temporary files are ignored. package-lock.json and Cargo.lock are not ignored.

## Dependencies

Runtime npm dependency:

- @tauri-apps/api 2.12.1

Development npm dependencies:

- @tauri-apps/cli 2.12.1
- svelte 5.57.1
- @sveltejs/kit 2.70.3
- @sveltejs/adapter-static 3.0.10
- @sveltejs/vite-plugin-svelte 7.3.1
- svelte-check 4.7.6
- typescript 6.0.3
- vite 8.3.2

Direct Rust dependencies: tauri 2.12.1, serde 1.0.229 (derive); build dependency tauri-build 2.7.1.

No UI framework, database, authentication, HTTP client, or sync dependency was added. The template opener dependencies were removed.

npm audit reports 3 low-severity findings in the development dependency chain (@sveltejs/adapter-static → @sveltejs/kit → cookie). The underlying advisory is [GHSA-pxg6-pf52-xh8x](https://github.com/advisories/GHSA-pxg6-pf52-xh8x). npm proposes major-version framework upgrades; no force upgrade or dependency override was applied. The Tauri frontend is a static SPA and does not run a SvelteKit server in the shipped application.

## Known Limitations

- Not compiled on Windows.
- Not run on a physical Windows machine.
- SQLite is not implemented.
- Vocabulary is not implemented.
- SRS is not implemented.
- Sync is not implemented.
- Minimum-width layout and Windows font fallback still need separate platform testing.
- Official template icons are placeholders, not final Kotoba branding.
- Three low-severity npm development dependency audit findings remain.
- Windows CI/build verification will be added in Phase 1.

## Phase 0 Result

PASS — required frontend/Rust checks, development launch, runtime IPC, Japanese glyph rendering, and repository isolation are verified. Windows platform validation remains Phase 1 work; low-severity npm audit findings are recorded above.
