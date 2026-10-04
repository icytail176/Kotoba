# Kotoba Windows Phase 1 Report

## Repository

- Branch: feature/windows-client
- Phase 0 commit: 1fac70f509605035880f8dbd28fa6b17ab06cf1f (Initialize Windows client foundation)
- Phase 1 commit: 956e510dff35aa848613386a9ca8c3f40a03eb00 (Add Windows CI build)
- Remote branch: origin/feature/windows-client
- Base main commit: 21ea7c6b83dc18d9283f190c415e666f02463e83

Phase 0 was rechecked before committing: frontend check/build, cargo fmt/check/clippy all passed locally. IDE files, node_modules, build/dist/.svelte-kit, target, debug application packages, and the temporary runner were excluded. Both lockfiles were committed. No Phase 0 source or product behavior was changed during Phase 1.

This report is a separate documentation-only commit after the validated Phase 1 commit. Its commit message uses [skip ci] to avoid rerunning an identical native build solely to save this completed report. The validated source, lockfiles, configuration, and workflow remain exactly those at the Phase 1 SHA above; this does not represent a CI validation of the later documentation commit.

## CI

- Workflow: Kotoba Windows Build
- File: .github/workflows/windows-build.yml
- Workflow ID: 374570895
- Runner: GitHub-hosted windows-latest, Windows X64
- Run ID: 37201244471
- Run URL: https://github.com/icytail176/Kotoba/actions/runs/37201244471
- Trigger: push to feature/windows-client
- Final status: completed / success
- Job duration: 7m44s
- CI failure / repair iterations: none

Only feature/windows-client pushes affecting windows/** or this workflow, and manual workflow_dispatch, are enabled. main is not monitored. permissions are contents: read. No Release/tag/API publication step is present. No checks were removed or suppressed, and no missing installer/artifact is accepted.

## Environment

Recorded from the actual successful run:

- Windows runner: windows-2025-vs2026 (ImageOS win25-vs2026), image 20260925.250.1
- Node: 26.10.0
- npm: 11.21.0 (npm 11 explicitly selected after setup-node)
- Rust: 1.99.0 (b940084d7 2026-09-28)
- Cargo: 1.99.0 (5f94df478 2026-08-27)
- Rust toolchain/target/host: stable-x86_64-pc-windows-msvc / x86_64-pc-windows-msvc
- Components: rustfmt, clippy
- Tauri: CLI/API/runtime 2.12.1, from existing npm/Cargo lockfiles
- Visual Studio: C:\Program Files\Microsoft Visual Studio\18\Enterprise
- Windows SDK headers: 10.0.26100.0

Official actions used: actions/checkout@v7, actions/setup-node@v7, actions/upload-artifact@v7. Rust was installed with the runner's rustup; no additional Rust action or build-cache dependency was added.

The runner supplied C++ build tools and Windows SDK. Tauri's default Windows bundling successfully produced WiX MSI and NSIS installers, without Chocolatey installation or extra prerequisites. Existing bundle.targets=all was retained; no Windows source/config adjustment was required. The installer may install WebView2 using Tauri's default bootstrapper behavior on the user's machine; runtime behavior has not been tested here.

References: [GitHub runner images](https://github.com/actions/runner-images), [Tauri Windows prerequisites](https://v2.tauri.app/start/prerequisites/#windows), [Tauri Windows installers](https://v2.tauri.app/distribute/windows-installer/), [GitHub documentation-only workflow skipping](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs).

## Checks

| Check on Windows runner | Result |
| --- | --- |
| npm ci | PASS |
| frontend check (including --fail-on-warnings) | PASS; 0 errors, 0 warnings |
| frontend build | PASS |
| cargo fmt --check | PASS |
| cargo check --locked | PASS; native MSVC host |
| cargo clippy --locked -- -D warnings | PASS |
| npm run tauri build -- --ci | PASS |
| non-empty executable and installer verification | PASS |
| artifact upload | PASS |
| download and hash comparison | PASS |

PowerShell multi-command steps explicitly check native exit codes. npm commands run under windows/; Cargo checks run under windows/src-tauri/. npm uses ci, not install, for project dependencies. The Tauri CLI is the project's local dependency. The Windows build is native; no macOS cross-compilation was used.

## Windows Bundles

All downloaded hashes match the hashes printed by the Windows CI job. They provide Phase 1 traceability and are not official release checksums.

### MSI installer

- Filename: Kotoba_0.1.0_x64_en-US.msi
- Size: 2,035,712 bytes
- SHA-256: `dc7a85a848f5910cd585e1862db6b40a26e7a5e89f0d90adbec5419e357fe388`
- Downloaded file: /Users/fumi/Documents/Kotoba-Windows-CI/Phase1/bundle/msi/Kotoba_0.1.0_x64_en-US.msi

### NSIS installer

- Filename: Kotoba_0.1.0_x64-setup.exe
- Size: 1,373,528 bytes
- SHA-256: `0e22adbfd834d49598f2fe28809db70189cf9c8714aa1b819cf2b2a402659e72`
- Downloaded file: /Users/fumi/Documents/Kotoba-Windows-CI/Phase1/bundle/nsis/Kotoba_0.1.0_x64-setup.exe

### Standalone Windows executable

- Filename: kotoba-windows.exe
- Size: 4,231,168 bytes
- SHA-256: `48de362153c56ea94d71c051d4b28737df50c232c1333dd29e84c15b4f987c27`
- Downloaded file: /Users/fumi/Documents/Kotoba-Windows-CI/Phase1/kotoba-windows.exe

The application EXE has a valid PE header and x86_64 machine type (0x8664). The NSIS bootstrapper has a valid PE header and x86 machine type (0x14c), packaging the x64 application. The MSI has the expected Compound File Binary header. No downloaded binary was executed on macOS.

## Artifact

- GitHub Actions artifact name: kotoba-windows-phase1
- Artifact ID: 11303575149
- Downloaded path: /Users/fumi/Documents/Kotoba-Windows-CI/Phase1/
- Archive size: 4,930,584 bytes
- GitHub archive digest: `sha256:98ab685aba310d352e4a248283c510f126b3ee54d29290260b2dd72474a2837c`
- Source commit: 956e510dff35aa848613386a9ca8c3f40a03eb00
- Retention: 7 days (expires 2026-10-11 20:19 Asia/Shanghai)

Only the standalone executable, NSIS installer, and MSI were uploaded. Source, node_modules, and the full target directory were not uploaded. The download resides outside the repository and is not staged or committed.

## Windows Signing

NOT CONFIGURED.

No certificate was created, bought, configured, or used. The downloaded EXE files have empty PE certificate tables. Installers are unsigned, and Windows SmartScreen may warn. Signing belongs to a later release discussion.

## Platform Validation

- Windows compile/bundle: PASS
- Windows runtime: NOT TESTED
- Windows IME: NOT TESTED
- Windows DPI: NOT TESTED
- WebView2 runtime behavior: NOT TESTED

The source of truth for native compilation/bundling is the successful GitHub-hosted Windows job. No Wine, CrossOver, VM, or physical Windows launch was used.

## npm audit

Rechecked locally against the committed lockfile: 3 low-severity findings, 0 moderate/high/critical findings. The affected development chain is @sveltejs/adapter-static → @sveltejs/kit → cookie ([GHSA-pxg6-pf52-xh8x](https://github.com/advisories/GHSA-pxg6-pf52-xh8x)). This is the same finding recorded in Phase 0. No force fix, override, or major-version upgrade was applied. It did not block the native Windows build.

## macOS Project Isolation

`git diff main...HEAD --name-only` was checked against the allowed scope. All Windows development additions are under windows/ or the single .github/workflows/windows-build.yml file. Existing Kotoba/, KotobaTests/, Kotoba.xcodeproj/, macOS resources, root README, Swift/schema/seed/backup code, versions, and release files are unchanged. No main merge, PR, tag, or GitHub Release was created.

## Known Limitations

- No physical Windows startup or installer execution yet.
- SQLite is not implemented.
- Vocabulary is not implemented.
- SRS is not implemented.
- Sync is not implemented.
- Windows signing is not configured.
- IME, DPI, WebView2 behavior, and SmartScreen experience need later Windows testing.
- Placeholder template icons remain; no product features or Phase 2 work were added.
- CI artifacts expire after seven days and are not release downloads.

## Phase 1 Result

PASS.

All required checks and native Windows executable/installer builds passed. Both installer formats were downloaded and statically checked against the successful run's hashes and commit metadata. Runtime testing remains explicitly unverified.
