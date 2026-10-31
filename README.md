<div align="center">

<img src="src-tauri/icons/128x128@2x.png" width="112" alt="Loci logo" />

# Loci

**One desktop app for every agent CLI you already use.**

Projects are plain folders. Sessions run through the agent CLIs installed on your machine.<br />
Notes, canvases and resident agents live next to the conversation.

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
- **Resident agents.** Long-lived agents that belong to no project: one conversation you keep coming back to, standing instructions, a memory, habits that run on a schedule, and courses, documents and notes beside the chat. They ask with choices to click, and reply with cards. See [Agents](#agents).
- **Source questions and PDF notes.** Attach excerpts from files, PDFs, web pages or conversations to a question. Select PDF passages to save highlights, notes and links back to discussions; web sources accept a URL and a pasted excerpt. See [docs/learning.md](docs/learning.md).
- **Themes, wallpapers and fonts.** Settings → Appearance offers 22 Omarchy themes, matching code highlighting and 72 wallpapers, alongside custom backgrounds and system-installed fonts. Existing background effects, visibility settings and custom accent colors still apply. See [docs/themes.md](docs/themes.md).
- **Settings in English or Simplified Chinese.** Settings can follow the system language or use your choice in General → Settings language. The workspace stays in English.
- **Local-first.** A local SQLite database, no account, no analytics, no auto-updater. See [Data and privacy](#data-and-privacy).

## Install

### Download

Installers for macOS (Apple silicon and Intel) and Linux (x64) are on the [Releases](https://github.com/Umupa/Loci/releases) page, and an installed Loci updates itself from there (**Settings → General → About**). Release builds are not notarized, so macOS asks you to confirm the first time you open one. [CHANGELOG.md](CHANGELOG.md) lists what changed in each version.

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
npm run app:dev        # run Loci Dev with hot reload
npm run tauri build    # build an installer for your platform
```

What you run from source is **Loci Dev**: a separate app with its own data folder, so it can run beside an installed Loci without touching your notes or agents. `npm run install:local` (macOS) builds this checkout as the real Loci and installs it to `/Applications`. See [docs/releasing.md](docs/releasing.md).

On macOS, `./script/build_and_run.sh --verify` builds and launches a release bundle of Loci Dev (it first stops any running copy built from this checkout; `--help` lists the debug and log options).

### Before the first session

- Install and sign in to at least one supported agent CLI. Loci looks for each CLI on your `PATH` and in the usual install locations. **Settings → Agent CLIs** lets you point at a specific binary, set a default model, and hide CLIs you do not use.
- Install Node.js 20.11+ (or Bun) if you want the built-in MCP servers (`loci_excalidraw`). Without it sessions still start; Settings and the canvas panel say what is missing.

## Supported agent CLIs

| CLI | Notes |
| --- | --- |
| Claude Code, Codex | The full feature set: account management and usage meters, the built-in MCP server |
| Antigravity, Pi | Chat with model and permission selection, plus the canvas tools through Loci's CLI |
| Cursor, Grok Build, OpenCode, omp, fx, Hermes Agent | Chat with model and permission selection through the CLI's own protocol. How much more shows up (questions, plans, tool details) depends on what the CLI reports |

Details worth knowing:

- Accounts and usage meters are implemented for Claude Code and Codex only.
- Antigravity runs through its own ACP server. If you are asked to authenticate, use **Sign in to Antigravity** in the app; signing in to the interactive `agy` does not carry over.
- Antigravity and Pi call the canvas tools by running a command, so they are told about them in the conversation rather than through a tool list. Pi never asks before it acts, so drawing does not ask there either, and in Plan mode Pi has no shell and cannot reach these tools.
- fx does not support attachments yet.
- CLIs that are not installed still appear in Settings, with an install hint.

## Slash commands

Commands work at the start of a prompt.

| Command | What it does |
| --- | --- |
| `/operator` | Give this thread access to Loci sessions, folders, notes and canvases |
| `/btw` | Ask a read-only side question about the current turn |
| `/draft` | Save this message without starting the agent |
| `/compact` | Summarize older conversation context to free space |
| `/mcp` | Find an MCP server for this message |
| `/add-to-folder` | Place this session in an existing or new sidebar folder |


## Agents

Press **+** beside *Agents* on the rail to open a blank conversation using your default model. Give it a purpose or a first task in chat. Read and edit its standing instructions under **Settings → Soul**, and change its name, role, model and projects in Settings. You can also ask the agent to revise its Soul through chat. Loci supplies identity, projects, memory and tool availability as context. The user and Soul define the agent's behavior.

- **It stays.** An agent has one conversation that never ends, a soul (its standing instructions) and memory it can update through the app CLI. Both are files in Loci's data folder, outside your repositories, and they survive a change of model.
- **It works in your projects.** Give it projects under Settings. It can work with their files while you discuss the work in the same agent conversation.
- **Habits.** Things it does on a schedule while Loci is open, messaging you only when something is worth saying.
- **Cards.** A reply can carry more than text: a question with choices to click, a document that opens beside the chat, a checklist you tick, a mind map that folds, a Mermaid diagram, or a link to a canvas. Checklist actions send a message.
- **Overview.** Courses, documents, notes, habits and canvases live beside the chat. Open a course, document or editable note in the panel, return to its list, or expand it into a workspace pane. Notes saved here stay associated with the agent and are also available in Notes. Habits show recent reports and failures.
- **A tutor, for example.** Ask an agent to teach you a subject and keep your progress in memory. You can set its teaching approach in Soul and ask it to write a roadmap when you want to continue.

What an agent does is its prompt at work, so how well it goes depends on the model behind it.

On macOS, agent and document titles share the window's top row. Drag empty space in that row to move the window; use a pane's grip to rearrange it.

## Data and privacy

- **Where your data is.** Sessions, notes, canvases, source references, PDF annotations, layout and reminders are in `loci.db` (SQLite) inside the app data folder `com.loci.desktop`: `~/Library/Application Support/com.loci.desktop` on macOS, `~/.local/share/com.loci.desktop` on Linux, `%APPDATA%\com.loci.desktop` on Windows. Pasted images and isolated provider accounts live beside it. Your project files stay in your own folders. PDF annotations do not rewrite the PDF.
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
npm run app:dev       # Loci Dev with hot reload
npm run check         # what CI runs: Vitest, tsc, cargo fmt, clippy and cargo test
npm run build         # type-check and build the web bundle
```

| Command | What it does |
| --- | --- |
| `npm test` / `npm run test:watch` | Vitest, once or in watch mode |
| `npm run check:web` | Vitest and `tsc --noEmit` |
| `npm run check:rust` | `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test` |
| `npm run set-version -- 0.1.1` | Bump the version in every file that carries it |
| `npm run tauri:stable` | Loci Dev without reloading when files change (no hot reload, no Rust rebuild) |
| `npm run install:local` | Build this checkout as the installed Loci and put it in `/Applications` (macOS) |
| `npm run release -- 0.2.0` | Release a version from main (maintainers; see [docs/releasing.md](docs/releasing.md)) |

Layout:

```text
src/                      React front end
  app/                    window shell and workspace composition
  features/               sessions, agents, notes, canvas, projects, search, settings, skills, ...
  integrations/harness/   agent CLI protocol core and the ten providers
  platform/tauri/         thin wrappers over Tauri commands
  shared/                 UI components, hooks and utilities
src-tauri/                Rust back end: processes, SQLite stores, app control, MCP resources
  resources/              bundled MCP servers (excalidraw-mcp)
docs/                     guides and design records
scripts/                  releases, version bump, vendoring and live protocol probes
```

[docs/architecture.md](docs/architecture.md) explains how the pieces fit together. Contributions are welcome; please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## Documentation

The [documentation index](docs/README.md) lists every guide. The design record for the canvas MCP is written in Chinese.

## License

Loci is released under the [MIT License](LICENSE). It is derived from an earlier MIT-licensed project and bundles the official Excalidraw MCP server, also MIT; [NOTICE](NOTICE) records the origin, revisions and trademarks. Loci is not affiliated with the makers of the agent CLIs it can drive.
