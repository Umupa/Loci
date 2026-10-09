# Contributing to Loci

Thanks for taking the time to improve Loci. This guide covers how to set up, what to run before you send a change, and what makes a change easy to review.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- **Bugs and small fixes:** open a pull request. For a bug, an issue with steps to reproduce helps others who hit it.
- **Features, and anything that touches several areas:** open an issue first so we can agree on the approach before you spend time on it. Some things were removed on purpose; check [Out of scope](docs/architecture.md#out-of-scope).
- **Security problems:** do not open a public issue. See [SECURITY.md](SECURITY.md).

## Set up

You need Node.js (the version in `.nvmrc`, or any release that satisfies `engines` in `package.json`), a stable Rust toolchain with `rustfmt` and `clippy`, and the [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/) for your OS. On Debian and Ubuntu:

```sh
sudo apt install build-essential curl wget file libwebkit2gtk-4.1-dev \
  libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev libdbus-1-dev
```

Then:

```sh
git clone https://github.com/Umupa/Loci.git
cd Loci
npm ci
npm run tauri dev
```

The page that Vite serves on its own (`npm run dev`) is not useful in a browser, because it needs the Tauri APIs. Run the app with `npm run tauri dev`.

You also need at least one supported agent CLI, signed in, to exercise a session end to end. Most of the code can be worked on and tested without one.

On macOS, debug builds relaunch from a generated `Loci.app` bundle, because `tauri dev` otherwise runs a bare binary and the Dock paints its icon wrongly. Set `LOCI_DEV_APP_NAME` to change the bundle's name.

## Check your change

```sh
npm run check
```

This is what CI runs. It is `npm run check:web` (Vitest and `tsc --noEmit`) followed by `npm run check:rust` (`cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test`). Run `cargo fmt` to fix formatting. There is no formatter for TypeScript, so match the code around your change.

While working, `npm run test:watch` and `cargo test <name>` are faster. Test files sit beside the code they test (`*.test.ts`, and `#[cfg(test)]` modules in Rust).

## Make the change

- **Branches:** start from `main` and name the branch for the kind of change: `feat/...`, `fix/...`, `docs/...`, `chore/...`.
- **One topic per pull request.** Smaller changes get reviewed sooner.
- **Add tests.** A bug fix should come with a test that fails without the fix. If something can only be checked by running the app, say how you checked it in the pull request.
- **Match the surrounding code:** naming, structure and comment density. Comments explain why, not what.
- **Commit messages** follow Conventional Commits, as in the history: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `perf:`, `ci:`, `chore:`, in the imperative (`fix: keep the draft when a session is archived`).
- **Do not commit generated files.** `dist/`, `target/` and `src-tauri/gen/schemas` are ignored.
- **User-visible changes** get a line under *Unreleased* in [CHANGELOG.md](CHANGELOG.md).
- **Platform code** has to keep compiling on the other platforms. Guard it with `cfg` and keep shared logic outside the guard.

## Take extra care with

- **The learning map (`src/features/learn`).** Its rules are enforced in the app so they hold for any model. Read [docs/learn.md](docs/learn.md) before changing them, and do not move a rule into the prompt. What the agent does around the map (the interview, the roadmap, gathering the readings) is the other way round: it is the prompt in `learnCommand.ts`, on purpose, so improve it there and not with app code, and say which agent and model you ran it with.
- **The vendored Excalidraw MCP server (`src-tauri/resources/excalidraw-mcp/official`).** It is shipped unmodified and its hashes are recorded in `SOURCE`. Never edit it by hand; update it with `node scripts/vendor-excalidraw-mcp.mjs`.
- **The control channel and permissions.** A new namespace, a new bridge, or a new place a token is passed widens what an agent can reach. Treat it as a security change and describe the reasoning in the pull request.
- **SQLite tables.** There is no migration framework, and for many people the database is the only copy of their notes and canvases. A change to an existing table must keep reading databases written by older versions.
- **New agent CLIs.** Copy the shape of an existing adapter (see [Agent CLIs](docs/architecture.md#agent-clis)) and say which CLI version you tried it with.

## Dependencies

`package-lock.json` and `Cargo.lock` are committed; install with `npm ci`. When you add or update a dependency, commit the lockfile with it and say why the dependency is worth its weight. Dependabot proposes routine updates every week.

## Documentation

User-facing documentation is written in English, with [README.zh-CN.md](README.zh-CN.md) as the Chinese translation of the README. Keep the two in step when you change either. Design records may be written in another language; say which at the top, and add them to the [documentation index](docs/README.md).

## Releases (maintainers)

1. `npm run set-version -- X.Y.Z` updates the version in `package.json`, `package-lock.json`, `Cargo.toml`, `Cargo.lock` and `src-tauri/tauri.conf.json`.
2. In [CHANGELOG.md](CHANGELOG.md), rename *Unreleased* to the new version and date, and start a new empty *Unreleased*.
3. Commit as `chore: release vX.Y.Z`, then tag it: `git tag vX.Y.Z && git push origin main vX.Y.Z`.
4. The [release workflow](.github/workflows/release.yml) builds installers for macOS (Apple Silicon) and Linux (x64) and attaches them to a draft release. Open the draft, check the artifacts, and publish it.

Release builds are not code-signed or notarized. Add a platform to the workflow's matrix only after someone has run the app there; Windows is not in it yet for that reason.
