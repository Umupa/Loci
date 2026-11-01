<div align="center">

<img src="src-tauri/icons/128x128@2x.png" width="112" alt="Loci logo" />

# Loci

**An AI-native learning workspace for engineers.**

**One resident mentor per topic. It brings the first-hand sources — documentation, specifications, papers and source code — and reads them with you.**

[![CI](https://github.com/Umupa/Loci/actions/workflows/ci.yml/badge.svg)](https://github.com/Umupa/Loci/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

English · [简体中文](README.zh-CN.md)

</div>

---

Loci is a local-first desktop workspace for learning technical subjects with an agent. Each mentor is a long-lived agent for one topic: a Soul (its standing instructions), a memory, and a library of courses, documents, notes and canvases beside one conversation. The mentor gathers primary sources and reads them with you. It runs through the agent CLI you already signed in to — Claude Code or Codex — so there is no model API key to add, and it has no server of its own. Your data stays on your machine: each mentor's material in a folder of plain files, the rest in one local SQLite database.

> [!NOTE]
> Loci is early software (v0.1). The interface, the data model and the bundled MCP tools may still change. See [Platform support](#platform-support) for what has and has not been tried on each OS.

## The learning loop

1. **Set the goal.** Tell the mentor what you want to learn. It asks one question at a time until the goal and your background are clear.
2. **Gather first-hand sources.** It finds official documentation, specifications, papers and source code, and keeps them where the course can point at them.
3. **Arrange a course.** It orders the sources into chapters and lessons. Each lesson points at the passage, page or file to read.
4. **Read and ask.** You read the original in Loci. Attach a passage from a document, a PDF, a web page or a conversation to a question; the answer can refer back to that excerpt.
5. **Keep what you learned.** Write notes and draw canvases beside the chat. The mentor records progress in its memory, so the next session continues where you stopped.

## Mentors

Press **+** on the mentor rail (or ⌘T) to create one. Use one mentor per topic. Start from **Mentor**, **Lens**, or a blank agent. The **Mentor** template agrees on a goal one question at a time, gathers first-hand sources, arranges them into a course, and tests your understanding as you read. **Lens** takes a repository, clones it, writes a one-page brief, and builds a code-tour course of the files worth reading.

Every mentor has:

- **A Soul.** Standing instructions for how it teaches, what it expects from you and what to avoid. Edit it in the mentor's settings under **Soul**, or ask the mentor to revise it in chat.
- **A memory.** Facts and topic notes the mentor maintains through the built-in `app` CLI. They are files in Loci's data folder, so a change of model keeps them.
- **A library.** Courses, documents, notes and canvases beside the conversation. A course is what you read; documents are the material it points at; notes are yours to edit; canvases are Excalidraw drawings. The mentor saves documents and courses through `app documents.write` and `app courses.write`.
- **One conversation.** A mentor keeps a single conversation. The lesson, document or note open beside it is passed as context, so "this" and "the passage" refer to what you are reading.
- **Cards.** A reply can carry a question with choices to click, a document to open, a checklist, a mind map, a course, a code diff, a Mermaid diagram, or a link to a canvas.

A mentor works through the CLI: it can clone a repository, run code and prepare experiments on your machine. It starts with **Full access**, so it does not stop for a prompt on every step; change that in the mentor's settings, or the default for new mentors in **Settings → Your mentors**.

What a mentor does is its prompt at work, so how well it goes depends on the model behind it.

Each mentor has its own workspace: the open course's outline and the library on the left, the reader in the middle, and the conversation on the right. Opening anything (a lesson, a source, a note, a canvas, a file, or a session the mentor started) replaces what the reader shows; nothing opens in a new tab or window. Coming back to a mentor reopens the lesson it was showing. ⌘K finds a mentor or anything in its library, ⌘1–9 switch mentors, ⌘W closes the reader, and ⌘B and ⇧⌘B fold the library and the conversation.

## Reading and sources

Questions can carry an excerpt. Select code or text in a file and choose **Ask agent** or **Add to chat**; select a passage in a PDF or a conversation; or add a web source with a URL and the passage pasted in (Loci does not fetch the page for this). The excerpt is shown with the message and passed to the CLI as text.

For PDFs, select text and choose **Ask agent** to ask about it, or **Highlight** to save a highlight. Click a highlight to add a note, ask about it, open a linked discussion or delete it. The **PDF annotations** list in the reader toolbar shows every highlight. Highlights, notes and discussions are stored in the local `loci.db`; the PDF itself is not rewritten. Pages need a text layer; there is no OCR. See [docs/learning.md](docs/learning.md).

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

- Install and sign in to Claude Code or Codex. These are the two supported CLIs. Loci looks for each CLI on your `PATH` and in the usual install locations. **Settings → Agent CLIs** lets you point at a specific binary, set a default model, and hide CLIs you do not use.
- Install Node.js 20.11+ (or Bun) if you want the built-in MCP server (`loci_excalidraw`). Without it sessions still start; Settings and the canvas panel say what is missing.

## Supported agent CLIs

Loci starts a CLI installed on your machine and speaks its protocol; it does not run models itself. Claude Code and Codex are supported. The other eight adapters are kept and are experimental.

| CLI | State |
| --- | --- |
| Claude Code, Codex | Supported: chat, tools and permissions, and the built-in canvas MCP server |
| Antigravity, Pi, Cursor, Grok Build, OpenCode, omp, fx, Hermes Agent | Experimental: chat with model and permission selection. What else shows up (questions, plans, tool details) depends on what the CLI reports |

Each CLI keeps its own sign-in and settings. Each session picks a model and a permission mode: Supervised, Auto-accept edits, Auto or Full access.

Details worth knowing:

- Antigravity runs through its own ACP server. If you are asked to authenticate, use **Sign in to Antigravity** in the app; signing in to the interactive `agy` does not carry over.
- Antigravity and Pi call the canvas tools by running a command, so they are told about them in the conversation rather than through a tool list. Pi never asks before it acts, so drawing does not ask there either, and in Plan mode Pi has no shell and cannot reach these tools.
- fx does not support attachments yet.
- CLIs that are not installed still appear in Settings, with an install hint.

## Slash commands

Commands work at the start of a prompt.

| Command | What it does |
| --- | --- |
| `/btw` | Ask a read-only side question about the current turn |
| `/draft` | Save this message without starting the agent |
| `/compact` | Summarize older conversation context to free space |
| `/mcp` | Find an MCP server for this message |

## Command line

`loci` drives a running Loci from a terminal: create mentors and talk to them, write sources, courses and notes, and open them in the reader. Tests and agents outside Loci use it. **Settings → General → Command line** puts it on your PATH and can turn it off. See [docs/cli.md](docs/cli.md).

## Appearance and language

**Settings → Appearance** offers 22 Omarchy themes, matching code highlighting and 72 wallpapers, alongside system-installed fonts and custom accent colors. **Settings → General → Settings language** can follow the system language or use English or Simplified Chinese. The workspace stays in English. See [docs/themes.md](docs/themes.md).

## Data and privacy

- **Where your data is.** Each mentor's library, courses, notes, drawings, Soul and memory are files in its own folder, `~/Loci/<mentor>/`; you and the mentor can edit them, and Loci shows the change. Conversations, reading progress, highlights and an index of those folders are in `loci.db` (SQLite) inside the app data folder `com.loci.desktop`: `~/Library/Application Support/com.loci.desktop` on macOS, `~/.local/share/com.loci.desktop` on Linux, `%APPDATA%\com.loci.desktop` on Windows. Pasted images live beside it. Your project files stay in your own folders. PDF annotations do not rewrite the PDF.
- **What Loci sends over the network.** Loci has no analytics or crash reporting. An installed Loci checks GitHub Releases for updates a little after launch and every six hours, and asks before installing one; a build from source does not update itself. Beyond what the agent CLIs do with their own providers, Loci fetches the title and icon of public links shown in a conversation (loopback and private addresses are refused).
- **The command line.** `loci` in a terminal can drive Loci while it runs. It needs a token that only your user account can read, and it can be turned off in **Settings → General → Command line**.
- **What agents can do.** An agent runs with your user's permissions. The permission mode only decides when Loci asks you before the CLI acts, so choose it with the same care as in the CLI itself. **Full access**, what a mentor starts with, allows commands, edits and supported MCP confirmations without prompts.

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
  app/                    window shell: the mentor rail, keys and session wiring
  features/               mentor workspace, sessions, agents, learning, notes, canvas, settings, skills, ...
  integrations/harness/   agent CLI protocol core and the ten CLI adapters
  platform/tauri/         thin wrappers over Tauri commands
  shared/                 UI components, hooks and utilities
src-tauri/                Rust back end: processes, SQLite stores, app control, MCP resources
  resources/              bundled MCP servers (excalidraw-mcp)
docs/                     guides and design records
scripts/                  releases, version bump, vendoring and live protocol probes
```

[docs/architecture.md](docs/architecture.md) explains how the pieces fit together. Contributions are welcome; please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## Documentation

The [documentation index](docs/README.md) lists every guide. [docs/roadmap.md](docs/roadmap.md) (in Chinese) sets out the positioning and the stages ahead. The design record for the canvas MCP is written in Chinese.

## License

Loci is released under the [MIT License](LICENSE). It is derived from an earlier MIT-licensed project and bundles the official Excalidraw MCP server, also MIT; [NOTICE](NOTICE) records the origin, revisions and trademarks. Loci is independent of the makers of the agent CLIs it runs.
