# Architecture

How Loci is put together, for people who want to change it. It covers the moving parts and the rules that are easy to break by accident. The design records for the canvas MCP server and `/learn` go deeper; they are linked from the [documentation index](README.md).

## The shape of the app

Loci is a [Tauri 2](https://v2.tauri.app/) app: a Rust host process and the system WebView running a React 19 single-page app.

- **Rust (`src-tauri/src`)** owns what a WebView cannot do: starting and killing agent processes with pipes, files and clipboard, SQLite, notifications, window chrome, and the local control channel.
- **TypeScript (`src`)** owns the product: the agent protocols, the session model, every screen. The Rust commands are generic (`harness_spawn`, `harness_write`, `harness_kill`, `read_text_file`, ...), so protocol work rarely needs a Rust change.

```text
┌──────────────────────────── Loci window ─────────────────────────────┐
│ WebView (React)                           Rust host (src-tauri)       │
│  app/  features/  integrations/harness     processes · files · SQLite │
│        │  invoke / events  ◀────────────▶  notifications · control    │
└────────┼──────────────────────────────────────────────┬──────────────┘
         │ HarnessEvent stream                          │ spawn, stdio pipes
         ▼                                              ▼
   session UI, notes, canvases            agent CLI (claude, codex, ...)
                                                        │ stdio MCP
                                                        ▼
                                  loci_excalidraw / loci_learn (Node or Bun)
                                                        │ loopback + per-turn token
                                                        ▼
                                            control.rs ──▶ the owning window
```

## Agent CLIs

Everything about talking to an agent lives in `src/integrations/harness`.

- `core/` is provider-neutral: the adapter registry, the `HarnessEvent` stream every provider emits, the JSON-RPC and ACP clients, the process bridge to Rust (`child.ts`), CLI availability and sign-in checks.
- `providers/<name>/` has one directory per CLI. It turns the CLI's protocol into `HarnessEvent`s, and turns Loci's inputs (model, permission mode, attachments, MCP servers) into that CLI's flags or requests. Claude Code is driven through its stream-json control protocol, Codex through `app-server` JSON-RPC, and Cursor, Grok Build, fx, Hermes Agent and Antigravity through the shared ACP client.
- An adapter implements `HarnessAdapter` (`core/registry.ts`) and is registered in `core/register.ts`. `providers/fx` is a compact example to copy from.

Agent processes are children of Loci. On exit Loci kills them, and each is started with `LOCI_HARNESS_PARENT` set to Loci's process id so that cleanup only touches processes this copy of Loci started and never agents that belong to another app. On Windows a job object also kills the tree if Loci crashes.

Permission modes are not enforced by Loci's own sandbox. Loci answers the CLI's approval requests according to the mode (or leaves them to you), so what a mode really allows is decided by the CLI.

## Sessions and the workspace

- `features/sessions` holds the session model (a list of typed blocks), transcript rendering, the composer, slash commands and the submission pipeline (`app/hooks/useSessionSubmission.ts`).
- `features/workspace` and `app/` hold tabs and the split-pane tree, which is saved as a snapshot so a restart restores the layout.
- `features/notes`, `features/canvas`, `features/learn`, `features/projects`, `features/search`, `features/settings`, `features/skills` and `features/notifications` are feature folders. Code shared by several features lives in `shared/`, and the thin wrappers over Tauri commands in `platform/tauri/`.

## Storage

State lives in SQLite (`rusqlite`, bundled) as `loci.db` in the app data folder `com.loci.desktop`, next to pasted images and isolated provider accounts.

| Table | Rust module | Holds |
| --- | --- | --- |
| `sessions`, `in_flight_sessions` | `session_store.rs` | session transcripts, and which sessions were still running at quit |
| `workspace_snapshot` | `session_store.rs` | tabs, panes, active project |
| `notes` | `notes.rs` | Markdown notes |
| `canvases`, `canvas_checkpoints` | `canvas.rs` | Excalidraw scenes and the checkpoint ids agents continue from |
| `session_reminders` | `reminders.rs` | manual reminders |
| `schema_migrations` | `session_store.rs` | the baseline schema version |

A canvas and its checkpoint are written in one transaction, so an agent is never given a checkpoint id the next call cannot find. Tables are created on demand with `CREATE TABLE IF NOT EXISTS` (the `ensure_*` helpers), and `schema_migrations` only records the baseline version. There is no migration framework yet, so a change to an existing table has to keep reading databases written by older versions: for many people this file is the only copy of their notes and canvases.

Loci reads a few things other tools already keep, and writes none of them: the sign-in identity a CLI cached on disk (`account_identity.rs`), the Claude Code token for its usage meter (`rate_limits.rs`), and Cursor's own store to recover sub-agent activity its ACP stream omits (`cursor_store.rs`).

## The control channel

`control.rs` is an authenticated loopback transport. Windows own execution; a caller never receives arbitrary Tauri command access or direct database write access.

1. When a turn starts, Loci gives that session a grant: an endpoint and a token, passed to the agent process as `LOCI_APP_ENDPOINT` and `LOCI_APP_TOKEN`. Credentials travel by environment variable and never appear on a command line.
2. The grant works only while that turn is active.
3. Requests are routed by namespace, and each namespace has its own rule:

| Namespace | Used by | Rule |
| --- | --- | --- |
| `app` | `/operator`, through the `app` subcommand of the desktop executable (`control_cli.rs`) | the thread must have opted in |
| `canvas` | the built-in Excalidraw MCP server | every session may draw, only in its own project |
| `learn` | the built-in learning MCP server | only threads where `/learn` has been used |

## Built-in MCP servers

Two stdio MCP servers ship in `src-tauri/resources` and run on the user's Node.js (20.11+) or Bun, located by `canvas_mcp.rs`.

- **`excalidraw-mcp/`** runs the official Excalidraw MCP server unmodified (`official/`; origin, version and hashes are in the `SOURCE` file beside it) behind `loci-bridge.mjs`, which swaps the official checkpoint store for Loci's canvases and adds tools to read canvases and update elements by id. To update the vendored server run `node scripts/vendor-excalidraw-mcp.mjs`. See [canvas-mcp.md](canvas-mcp.md).
- **`learn-mcp/loci-learn.mjs`** is a thin forwarder: each `loci_learn` tool call goes over the control channel to the window, where `src/features/learn/bridge.ts` applies it.

Claude Code receives them through `--mcp-config`, Codex through `-c mcp_servers.*` overrides. The Excalidraw server can be turned off in **Settings → MCP**. The learning server has no switch because it is attached only to threads where `/learn` is used.

## The learning map

The rules that make a learning map trustworthy are enforced in the window, not in the prompt, so they hold for any model. In `src/features/learn`:

- `model/` is pure logic with no UI or I/O: node states, host placement, the quote check, the revisit schedule.
- `bridge.ts` applies tool calls to the canvas and notes and refuses anything the rules forbid.
- `learnCommand.ts` defines `/learn` and its prompt, which is the learning skill itself: the overview, the interview and `profile.md`, the roadmap and `roadmap.md`, the readings gathered into `sources/`, and how to teach from them. The agent does that work with its own tools, so it is as good as the model. Change it in the prompt, and judge a change by running it with real agents (`scripts/acceptance/learn/`).
- `ui/LearnMapPanel.tsx` is the inspector and the revisit cover.

Canvas writes from other tools are refused on a learning map, which is how "the agent cannot move anything, and can take off only unexplored nodes nobody has touched" is enforced. Read [learn.md](learn.md) before changing any of this; its rules were chosen on purpose.

## Links between objects

Replies can link to notes (`loci://note/<id>`), canvases (`loci://canvas/<id>`), sessions and files. `shared/lib/appResourceLinks.ts` parses and builds them; the chat sanitizer allows only the `loci` scheme beyond its defaults, and checks resource kinds and ids before URL normalization. Links are handled by the current window and are not registered with the operating system.

## Platform code

- macOS: `macos.rs` (window chrome and background blur), notifications through `UNUserNotificationCenter`.
- Windows: `windows.rs` (job object so child processes die with the app), `tray.rs` (the way back to a window that closing hid).
- Linux: notifications through `notify-rust`, Wayland-aware clipboard reads.
- `src-tauri/tauri.conf.json` is the base configuration. Tauri merges `tauri.linux.conf.json` or `tauri.windows.conf.json` over it. `tauri.stable.conf.json` is only for `npm run tauri:stable`.

## Network and trust boundaries

- The WebView has a strict Content Security Policy (`'self'` for scripts, no remote frames) and the asset protocol is scoped to the app data folder.
- The Rust host makes only three kinds of outbound request: link previews (public hosts only, and every redirect is revalidated), the Claude Code usage endpoint (with the local token, which never leaves the host process), and loopback HTTP to servers that agent CLIs start (`harness_http` refuses anything that is not loopback).
- Agent processes run with the user's permissions. Anything that widens what an agent can reach, such as a new control namespace, a new bridge, or a new place a token is passed, needs the same care as a security change. See [SECURITY.md](../SECURITY.md).

## Testing

- `npm test` runs Vitest over `src/**/*.test.ts`. Pure logic has plain unit tests. The MCP bridges are tested against a real child process, and Excalidraw-dependent tests load the real library.
- `cargo test` covers the Rust modules.
- [`scripts/acceptance/`](../scripts/acceptance/README.md) holds probes that talk to real CLIs. They are run by hand and are not part of CI; the `*Live.test.ts` files use mocks and do not replace them.

## Out of scope

Loci was extracted from a larger coding-focused app by removing what an agent shell does not need. These were removed on purpose and are not planned: source control and worktree views, a code editor and file tree, an application terminal, inbox and chat-platform integrations, application-level multi-agent orchestration, scheduled automations, remote hosts over SSH, an auto-updater, and any telemetry. If you think one belongs back, open an issue to discuss it before writing code.

## Known limitations

- A `/btw` side question whose whole answer is a plan, with no text, ends with "returned an empty side answer". This was observed with Codex and is inherited from the code Loci was derived from.
- Agent CLIs are the ten built-in adapters. The ACP client is a reusable core, but there is no settings screen for adding your own ACP server.
- Windows has not been built or tried (see [Platform support](../README.md#platform-support)).
