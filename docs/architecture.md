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
                                                        │ stdio MCP, or `loci canvas|learn`
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
| `agent_transcript_pages` | `agent_transcript.rs` | older turns of an agent's conversation, moved out of its session |
| `schema_migrations` | `session_store.rs` | the baseline schema version |

Agents keep their own files beside the database, in `agents/<id>/` (see [Agents](#agents)).

A canvas and its checkpoint are written in one transaction, so an agent is never given a checkpoint id the next call cannot find. Tables are created on demand with `CREATE TABLE IF NOT EXISTS` (the `ensure_*` helpers), and `schema_migrations` only records the baseline version. There is no migration framework yet, so a change to an existing table has to keep reading databases written by older versions: for many people this file is the only copy of their notes and canvases.

Loci reads a few things other tools already keep, and writes none of them: the sign-in identity a CLI cached on disk (`account_identity.rs`), the Claude Code token for its usage meter (`rate_limits.rs`), and Cursor's own store to recover sub-agent activity its ACP stream omits (`cursor_store.rs`).

## The control channel

`control.rs` is an authenticated loopback transport. Windows own execution; a caller never receives arbitrary Tauri command access or direct database write access.

1. When a turn starts, Loci gives that session a grant: an endpoint and a token, passed to the agent process as `LOCI_APP_ENDPOINT` and `LOCI_APP_TOKEN`. Credentials travel by environment variable and never appear on a command line.
2. The grant works only while that turn is active.
3. Requests are routed by namespace, and each namespace has its own rule:

| Namespace | Used by | Rule |
| --- | --- | --- |
| `app` | `/operator` and agents, through the `app` subcommand of the desktop executable (`control_cli.rs`) | the thread must have opted in; an agent's conversation and its habit runs always have |
| `canvas` | the built-in Excalidraw server | every session may draw while the switch in **Settings → MCP** is on, only in its own project |
| `learn` | the built-in learning server | only threads where `/learn` has been used |

The switch is read when a turn starts and kept for that turn, so a change applies from the next turn and a running turn can finish. A provider may start its process under a generation-scoped id (`<session>#<n>`, as Antigravity does); the credential is looked up by the session that owns the process.

## Built-in MCP servers

Two stdio MCP servers ship in `src-tauri/resources` and run on the user's Node.js (20.11+) or Bun, located by `canvas_mcp.rs`.

- **`excalidraw-mcp/`** runs the official Excalidraw MCP server unmodified (`official/`; origin, version and hashes are in the `SOURCE` file beside it) behind `loci-bridge.mjs`, which swaps the official checkpoint store for Loci's canvases and adds tools to read canvases and update elements by id. To update the vendored server run `node scripts/vendor-excalidraw-mcp.mjs`. See [canvas-mcp.md](canvas-mcp.md).
- **`learn-mcp/loci-learn.mjs`** is a thin forwarder: each `loci_learn` tool call goes over the control channel to the window, where `src/features/learn/bridge.ts` applies it.

Claude Code receives them through `--mcp-config`, Codex through `-c mcp_servers.*` overrides. The Excalidraw server can be turned off in **Settings → MCP**. The learning server has no switch because it is attached only to threads where `/learn` is used.

### Agent CLIs that cannot be given an MCP server

Antigravity and Pi offer no way to attach an MCP server to one session without editing the user's own configuration, so they reach the same two servers through the desktop executable (`control_cli.rs`):

```sh
loci canvas create_view --input drawing.json
loci learn map_read
loci canvas --help
```

One call asks the running app which command starts the server (the reserved `mcp.server` request, answered by `control.rs` under the namespace's own rule), starts that server, makes the MCP handshake, calls the one tool and prints its text. The server is the same process an MCP client would attach, so the tools, their descriptions, the save receipts and every rule in the window are identical. Only the tools agents are given are accepted; the official widget's private tools stay out of reach.

What differs is how the agent finds out and how it is asked:

- **Knowing.** `useSessionSubmission.ts` appends a note to a turn: `<loci_canvas>` once per provider conversation while the switch is on, and the CLI wording of the `/learn` rules on the turn that used `/learn`. The harnesses that work this way are listed in `features/sessions/model/builtinCli.ts`.
- **Asking.** A provider that asks before running a command (Antigravity) sends the command with the request. `builtinCliCall` recognizes it only when it is exactly one tool call of this app's own executable, with nothing a shell would expand, chain or redirect; `builtinCliDecision` then answers with the rules of the MCP tools. Anything else is an ordinary command request. Pi never asks, and in Plan mode it has no shell, so the tools are out of reach there.
- **Showing.** The transcript names such a shell row as the canvas or learning call it is (`canvasToolCall.ts`, `learnToolCall.ts`).

A new provider that can run shell commands needs an entry in that list, and an approval branch like Antigravity's if it asks before running commands.

## Agents

An agent is long-lived and belongs to no project: a name, a pixel face in its own color, one conversation that never ends, and the projects it has been given. It lives on the rail above the projects. The code is in `src/features/agents`, with the wiring in `src/app/hooks/useAgents.ts`, `useAgentHabits.ts` and `useAgentDelegation.ts`.

- **Roster.** `model/agent.ts` keeps the agents in `localStorage` (`loci:agent-roster`). An agent's conversation is an ordinary session whose working folder is the home folder and whose permission mode starts as Auto. It is shown in a view that covers the workspace and is never part of a tab.
- **Files.** `agent.rs` keeps `SOUL.md`, `MEMORY.md`, `habits.json` and `memory/<topic>.md` under `<app data>/agents/<id>/`, never in a repository: an agent works in repositories with full file access, so a soul kept there could be rewritten outside the app's CLI or by a pull request. Paths are checked against that short list, writes are atomic and owner-only, and a save names the hash it read, so the user and the agent cannot overwrite each other. The same check is how two windows avoid running one habit twice.
- **What a turn carries.** `model/agentFiles.ts` puts a `<loci_context>` block ahead of the user's message: who the agent is, its projects, its soul, and the rules for memory, habits and delegation. A provider conversation is handed this once, and memory again only when it changes (`planAgentContext` records what was handed, by provider conversation and file hash). Bump `CONTEXT_VERSION` when the fixed rules change. The chat shows only what the user wrote.
- **Rotation.** The chat never ends, but the provider conversation behind it does. At 80% of the reported context window the next turn starts a fresh one (`model/agentRotation.ts`), briefed with the last two exchanges word for word and one line for each earlier one. No model is called to summarize; the full transcript stays readable through `app sessions.read`.
- **Paging.** The transcript itself would also grow without bound. Past 60 turns an idle chat that is not in view moves its oldest turns, down to 40, into `agent_transcript_pages` (`agent_transcript.rs`, `model/agentTranscript.ts`). The page is written before the session is trimmed and is keyed by its first block, so a crash in between archives nothing twice. The view offers the pages back with "Show archived history", above the transcript's own window of recent turns, and the agent's own `sessions.read` reaches into them. Pages are deleted with their session.
- **The app CLI.** An agent's conversation has `app` access in every turn, plus actions an ordinary thread does not have: `soul.*`, `memory.*`, `habits.*`, `sessions.stop`, `sessions.archive`, `sessions.delete`, and `"project"` on the session, folder and canvas actions, limited to the projects on its roster. Memory is changed only through the CLI, which dates entries, redacts common credential formats and moves old entries to an archive once `MEMORY.md` passes what loads into a turn.
- **Habits.** `useAgentHabits.ts` checks every minute while the app is open. A due habit runs in a hidden session (`ephemeral`: never saved, never shown, never counted) with full access, because nobody is watching it. With Codex the run uses an ephemeral thread, so it leaves nothing in the user's own Codex history; other CLIs keep whatever record they normally keep. Its last reply is posted to the agent's chat, or nothing when the reply is `NOTHING_TO_REPORT`. An approval the run asks for is put to the user in the agent's chat and the answer routed back. A run may work for an hour; one that came due more than two hours ago is skipped rather than caught up; one runs at a time.
- **Delegation.** A session an agent starts reports back by default. The ones started in the same agent turn form a group (`model/agentSessionCompletion.ts`); when that turn has ended and all of them have stopped, the agent is sent their results as one new turn, once it is idle and the user has nothing queued (`useAgentDelegation.ts`). Reports waiting to be delivered live in memory only, so they do not survive a restart.

Everything an agent can reach goes through the same control channel and the same window-side handlers as `/operator`. Widening what agents can do deserves the same care as any other change there. `sessions.delete` asks the user to confirm; an agent cannot remove a conversation on its own.

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

Loci was extracted from a larger coding-focused app by removing what an agent shell does not need. These were removed on purpose and are not planned: source control and worktree views, a code editor and file tree, an application terminal, inbox and chat-platform integrations, application-level multi-agent orchestration, standalone scheduled automations, remote hosts over SSH, an auto-updater, and any telemetry. Agents are the exception that came back in a narrower form: an agent can run habits on a schedule and start sessions that report to it, but there is no orchestration view, no automation list outside an agent, and nothing runs while the app is closed. If you think one belongs back, open an issue to discuss it before writing code.

## Known limitations

- A `/btw` side question whose whole answer is a plan, with no text, ends with "returned an empty side answer". This was observed with Codex and is inherited from the code Loci was derived from.
- Agent CLIs are the ten built-in adapters. The ACP client is a reusable core, but there is no settings screen for adding your own ACP server.
- Windows has not been built or tried (see [Platform support](../README.md#platform-support)).
