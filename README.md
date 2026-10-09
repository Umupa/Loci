<div align="center">

<img src="src-tauri/icons/128x128@2x.png" width="112" alt="Loci logo" />

# Loci

**One desktop app for every agent CLI you already use.**

Projects are plain folders. Sessions run through the agent CLIs installed on your machine.<br />
Notes, canvases and a learning map live next to the conversation.

[![CI](https://github.com/Umupa/Loci/actions/workflows/ci.yml/badge.svg)](https://github.com/Umupa/Loci/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

English · [简体中文](README.zh-CN.md)

</div>

---

Loci is a local-first desktop shell for agent CLIs, built with Tauri 2, Rust, React 19 and Tailwind 4. It does not run models and has no server of its own. It starts the CLIs you have installed, speaks their protocols, and gives them one place to work: tabs and split panes, a project sidebar, notes, Excalidraw canvases, reminders. Its data stays on your machine, mostly in one local SQLite database.

> [!NOTE]
> Loci is early software (v0.1). The interface, the data model and the bundled MCP tools may still change. See [Platform support](#platform-support) for what has and has not been tried on each OS.

## Features

- **Ten agent CLIs, one interface.** Claude Code, Codex, Cursor, Grok Build, OpenCode, Pi, omp, fx, Hermes Agent and Antigravity. Each CLI keeps using its own sign-in and settings. Pick the model and a permission mode (Supervised, Auto-accept edits, Auto, Full access) per session.
- **A workspace for long-running agents.** Tabs and drag-to-split panes, agent questions, plan and task display, a session list with folders, ⌘K search across sessions, image and document attachments, manual reminders and desktop notifications.
- **Notes and canvases as first-class objects.** Markdown notes you can `@`-mention in a prompt, and Excalidraw canvases. Replies can link to them with `loci://note/<id>` and `loci://canvas/<id>`, which open inside the current window.
- **Agents that can draw.** Claude Code and Codex sessions get a built-in `loci_excalidraw` MCP server: the official Excalidraw MCP server, unmodified, writing into Loci's own canvas store. Antigravity and Pi sessions reach the same tools through Loci's own CLI, with nothing to install or configure. Your hand edits are kept and the panel updates live. See [docs/canvas-mcp.md](docs/canvas-mcp.md).
- **`/operator`.** Let an agent drive Loci itself: read models, start and message sessions, arrange panes, organise folders, read and write notes and canvases. It uses an authenticated loopback channel that is valid only during the turn you enabled it for.
- **`/learn`.** Learn a subject on a map that grows only from what you can explain in your own words. See [Learning with Loci](#learning-with-loci).
- **Themes, wallpapers and fonts.** Settings → Appearance offers 22 Omarchy themes, matching code highlighting and 72 wallpapers, alongside custom backgrounds and system-installed fonts. Existing background effects, visibility settings and custom accent colors still apply. See [docs/themes.md](docs/themes.md).
- **Settings in English or Simplified Chinese.** Settings can follow the system language or use your choice in General → Settings language. The workspace stays in English.
- **Local-first.** A local SQLite database, no account, no analytics, no auto-updater. See [Data and privacy](#data-and-privacy).

## Install

### Download

Pre-built installers for macOS (Apple Silicon) and Linux (x64) will be attached to the [Releases](https://github.com/Umupa/Loci/releases) page once the first version is tagged. There are none yet, so for now build from source. Release builds are not notarized, so macOS will ask you to confirm the first time you open one.

### Build from source

You need:

| Tool | Version | Notes |
| --- | --- | --- |
| Node.js | 20.19+ or 22.12+ (24 recommended; `.nvmrc` pins it) | Vite 7 sets this floor |
| Rust | stable, with `rustfmt` and `clippy` | `rustup component add rustfmt clippy` |
| Platform libraries | see [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/) | Xcode Command Line Tools on macOS; WebKitGTK 4.1 and friends on Linux; MSVC and WebView2 on Windows |

```sh
git clone https://github.com/Umupa/Loci.git
cd Loci
npm ci
npm run tauri dev      # run with hot reload
npm run tauri build    # build an installer for your platform
```

On macOS, `./script/build_and_run.sh --verify` builds and launches a release bundle (it first stops any running copy built from this checkout; `--help` lists the debug and log options).

### Before the first session

- Install and sign in to at least one supported agent CLI. Loci looks for each CLI on your `PATH` and in the usual install locations. **Settings → Agent CLIs** lets you point at a specific binary, set a default model, and hide CLIs you do not use.
- Install Node.js 20.11+ (or Bun) if you want the built-in MCP servers (`loci_excalidraw`, `loci_learn`). Without it sessions still start; Settings and the canvas panel say what is missing.

## Supported agent CLIs

| CLI | Notes |
| --- | --- |
| Claude Code, Codex | The full feature set: account management and usage meters, the built-in MCP servers, `/learn` |
| Antigravity, Pi | Chat with model and permission selection, plus the canvas tools and `/learn` through Loci's CLI |
| Cursor, Grok Build, OpenCode, omp, fx, Hermes Agent | Chat with model and permission selection through the CLI's own protocol. How much more shows up (questions, plans, tool details) depends on what the CLI reports |

Details worth knowing:

- Accounts and usage meters are implemented for Claude Code and Codex only.
- Antigravity runs through its own ACP server. If you are asked to authenticate, use **Sign in to Antigravity** in the app; signing in to the interactive `agy` does not carry over.
- Antigravity and Pi call the canvas and learning tools by running a command, so they are told about them in the conversation rather than through a tool list. Pi never asks before it acts, so drawing does not ask there either, and in Plan mode Pi has no shell and cannot reach these tools.
- fx does not support attachments yet.
- CLIs that are not installed still appear in Settings, with an install hint.

## Slash commands

Commands work at the start of a prompt.

| Command | What it does |
| --- | --- |
| `/operator` | Give this thread access to Loci sessions, folders, notes and canvases |
| `/learn` | Learn a subject on a map that only records what you have explained yourself (Claude Code, Codex, Antigravity and Pi) |
| `/btw` | Ask a read-only side question about the current turn |
| `/draft` | Save this message without starting the agent |
| `/compact` | Summarize older conversation context to free space |
| `/mcp` | Find an MCP server for this message |
| `/add-to-folder` | Place this session in an existing or new sidebar folder |

## Learning with Loci

Type `/learn` in a Claude Code, Codex, Antigravity or Pi session. The project folder is the subject, for example `~/learn/kubernetes`, and Loci keeps a *learning map* canvas in it.

- **Solid means you explained it.** A node turns solid only when you say it in your own words. The agent records a quote, and Loci checks that quote against what you actually typed; it cannot be a summary or the agent's own explanation.
- **A profile, a roadmap and readings first.** Before teaching, the agent shows you the field, interviews you (goal, level, depth, language, how explanations land) and writes `profile.md`. It plans a route in `roadmap.md`, puts the stages and topics on the map as dashed nodes, and gathers the reading for every topic into `sources/`: complete texts in your language, translated in full when a source has no edition in it. This part is the skill's prompt, carried out with the agent's own search and file tools.
- **You say it, the agent draws.** The agent names what there is to learn: the roadmap's topics, and a few dashed nodes next to what you know. How they connect is yours to say. It cannot move anything on the map, can take off only dashed nodes nobody has touched, and does not get to call something mastered.
- **Revisits on a ladder.** Nodes come back after 1, 3, 7, 21, 60 and 150 days. During a revisit the map is covered and your earlier words are withheld until you have answered, so you explain from memory.
- **Judgments for subjects like investing.** A judgment node carries a date to look back on. The agent checks it against what you said before and names what you left out. It never gives buy or sell advice.

The map's rules live in the app, not in the prompt, so they hold whichever model you use. What the agent does around the map (the interview, the roadmap, the readings) is the prompt at work, and how well it goes depends on the model. The design, data model and a record of what was and was not verified are in [docs/learn.md](docs/learn.md) (written in Chinese).

## Data and privacy

- **Where your data is.** Sessions, notes, canvases, layout and reminders are in `loci.db` (SQLite) inside the app data folder `com.loci.desktop`: `~/Library/Application Support/com.loci.desktop` on macOS, `~/.local/share/com.loci.desktop` on Linux, `%APPDATA%\com.loci.desktop` on Windows. Pasted images and isolated provider accounts live beside it. Your project files stay in your own folders.
- **What Loci sends over the network.** Loci has no analytics, crash reporting or update checks. Beyond what the agent CLIs do themselves with their own providers, Loci fetches the title and icon of public links shown in a conversation (loopback and private addresses are refused), and for Claude Code it asks Anthropic's usage endpoint for your usage, using the local sign-in token that Claude Code already stores. That token is not saved anywhere else.
- **What agents can do.** An agent runs with your user's permissions. The permission mode only decides when Loci asks you before the CLI acts, so choose it with the same care as in the CLI itself. **Full access** allows commands, edits and supported MCP confirmations without prompts.

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Platform support

| Platform | State |
| --- | --- |
| macOS (Apple Silicon) | Primary development and manual testing platform |
| Linux | Builds, passes the test suite and runs; checked on Arch Linux ARM during development, and less used than macOS |
| Windows | Platform code and an installer configuration exist, but it has not been built or tried by the maintainers |

CI builds and tests the Rust and web code on Linux and macOS (see [.github/workflows/ci.yml](.github/workflows/ci.yml)).

## Development

```sh
npm ci
npm run tauri dev     # app with hot reload
npm run check         # what CI runs: Vitest, tsc, cargo fmt, clippy and cargo test
npm run build         # type-check and build the web bundle
```

| Command | What it does |
| --- | --- |
| `npm test` / `npm run test:watch` | Vitest, once or in watch mode |
| `npm run check:web` | Vitest and `tsc --noEmit` |
| `npm run check:rust` | `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test` |
| `npm run set-version -- 0.1.1` | Bump the version in every file that carries it |
| `npm run tauri:stable` | A dev instance that never reloads when files change (no hot reload, no Rust rebuild) |

Layout:

```text
src/                      React front end
  app/                    window shell and workspace composition
  features/               sessions, notes, canvas, learn, projects, search, settings, skills, ...
  integrations/harness/   agent CLI protocol core and the ten providers
  platform/tauri/         thin wrappers over Tauri commands
  shared/                 UI components, hooks and utilities
src-tauri/                Rust back end: processes, SQLite stores, app control, MCP resources
  resources/              bundled MCP servers (excalidraw-mcp, learn-mcp)
docs/                     guides and design records
scripts/                  version bump, vendoring and live protocol probes
```

[docs/architecture.md](docs/architecture.md) explains how the pieces fit together. Contributions are welcome; please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## Documentation

The [documentation index](docs/README.md) lists every guide. Design records for the canvas MCP and `/learn` are written in Chinese.

## License

Loci is released under the [MIT License](LICENSE). It is derived from an earlier MIT-licensed project and bundles the official Excalidraw MCP server, also MIT; [NOTICE](NOTICE) records the origin, revisions and trademarks. Loci is not affiliated with the makers of the agent CLIs it can drive.
