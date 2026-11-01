# Architecture

How Loci is put together, for people who want to change it. It covers the moving parts and the rules that are easy to break by accident. The design record for the canvas MCP server goes deeper; it is linked from the [documentation index](README.md).

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
                                                        │ stdio MCP, or `loci canvas`      
                                                        ▼
                                  loci_excalidraw (Node or Bun)             
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

## Sessions and the window

- `features/sessions` holds the session model (a list of typed blocks), transcript rendering, the composer, slash commands and the submission pipeline (`app/hooks/useSessionSubmission.ts`).
- The window is a rail of mentors (`app/shell/MentorRail.tsx`) beside the open mentor's workspace (`features/mentor`), or Settings. There are no tabs and no split panes: everything opens in the mentor's one reader. `app/hooks/useActiveMentor.ts` keeps which mentor is open (`loci:active-mentor.v1`, so a restart opens it again) and `useMentorView.ts` what each one shows.
- `app/hooks/useSessionStore.ts` holds the sessions the window has in memory: mentors' conversations, the sessions they start and whatever the reader shows. Sessions that belong to no mentor are not listed anywhere; a link, an approval toast or `sessions.start --reveal` shows one in the reader. `useIdleSessionDetach.ts` saves and releases idle sessions that are not on screen.
- Quit and restart keep only what resumes interrupted turns (`in_flight_sessions`). Keys are in `app/model/appKeys.ts` and `src-tauri/src/menu.rs`: ⌘T opens the mentor gallery, ⌘W closes the reader (the window when it is empty), ⌘1–9 and ⇧⌘[ ] switch mentors, ⌘B and ⇧⌘B fold the library and the conversation, ⌘K opens the mentor search palette (`features/mentor/ui/MentorSearch.tsx`), which finds mentors and the titles of what they keep.
- `features/agents`, `features/mentor`, `features/notes`, `features/canvas`, `features/learning`, `features/projects`, `features/settings`, `features/skills` and `features/notifications` are feature folders. Code shared by several features lives in `shared/`, and the thin wrappers over Tauri commands in `platform/tauri/`.

## Source context and reading

`features/learning` adds source metadata and local highlights and notes to ordinary sessions and agent conversations. These surfaces do not require a separate learning mode. `model/learningContext.ts` appends only provider-neutral source data to submitted prompts; the visible user block keeps its question and typed metadata separately. Queued messages and drafts carry the same metadata.



PDF.js renders selectable text in `features/files/ui/PdfView.tsx`. `model/pdfAnnotations.ts` measures selected text nodes, excludes page-container rectangles, and stores page-normalized rectangles across lines and pages. Highlights use pointer-transparent overlays; collapsed clicks are hit-tested by the page so dragging remains native text selection. `FilePane.tsx` registers the canonical document path and fingerprint, prepares sourced questions, edits local annotation notes and restores passages from annotation links. Locate file changes a document's path only when its fingerprint matches. OCR is outside this version.

Every reader shares one highlight and note model (`Annotation`): a mark names its target (a PDF, a library document or a text file) and, for text, a `TextAnchor` (the quote with 32 characters of context each side, an offset hint, the headings above it and, in a file, its lines). `model/textAnchor.ts` describes a DOM selection and finds it again: at its old place, else the repeat whose context fits best, else ignoring white space and case; a mark whose words are gone is kept and listed as changed, never deleted. `ui/useTextHighlights.ts` paints marks with the CSS Custom Highlight API, so rendered Markdown and code are never rewritten, and hit-tests clicks; `ui/useReadingMarks.tsx` is what each reader wires in (Ask, Highlight, Note, the popover and the list), and `ui/ReadingSelectionMenu.tsx` is the one selection menu (Ask <mentor> · Highlight · Note; ⌘L Quote and ⌥⌘M Comment as shortcuts). `DocumentBody` (library documents and lesson documents), `FilePane` (text, Markdown preview, PDF) and a lesson's code excerpt use them. PDF marks keep their page rectangles and, when new, a `TextAnchor` too. `model/annotationCounts.ts` gives per-lesson counts for the outline badge and the `annotations` commands.

The reader column reports where the learner is: readers mark their text with `data-reading-text` (and `data-reading-lines-from` for file lines), and `mentor/ui/useReadingPlace.ts` reads off the section, the first visible paragraph, the PDF page or the visible lines, and the reader's selection, which survives focus moving to the composer. `agents/model/agentReading.ts` adds them to `<reading_now>` as `place`, within hard limits (3 headings of 80 characters, 280 for the paragraph, 600 for the selection, 1.5 KB in all), and sends `"selection":"attached"` when the message already carries it as a source.

`LearningSource` describes a file, PDF passage, library document passage, web excerpt or conversation message. Sources are registered by id, rendered as chips, and linked with `loci://source/<id>`, optionally with a place: `#section=…&quote=…`, `#p7` or `#L12-40` (`shared/lib/appResourceLinks.ts` validates the fragment strictly). Navigation resolves the source in the trusted host, using the current registered PDF path after relocation; an id that is not a registered source names a document in the library of the mentor on screen. A document opens in the reader, or stays in the lesson already showing it; the reader scrolls to the quote (within the section when one is named), flashes it, and falls back to the section with a notice when the words changed. A PDF source opens in the PDF reader at `#p7`, and its `quote` is found in that page's text layer and flashed when the words are there. Sending a question about a saved annotation links it to the submitted user block; merely preparing a draft does not. Web-source entry takes a pasted passage and URL without fetching the page. See [learning.md](learning.md) for the workflow and authoring API.

## Storage

A mentor's content lives as files in its own folder; SQLite (`rusqlite`, bundled, `loci.db` in the app data folder `com.loci.desktop`) keeps what changes often or is not portable, and an index of the folders.

### Mentor folders

Each mentor is a folder under the mentors root: `~/Loci` for the installed app, `~/Loci-Dev` for Loci Dev, `~/Loci-Dev-<suffix>` for any other build (a QA bundle), or `LOCI_MENTORS_ROOT` in builds other than the installed app. A folder directly under the root is a mentor when, and only when, it holds `mentor.json`; `repos/` (the shared clone root of 0.3) and anything else are ignored.

```text
~/Loci/<slug>/
├─ mentor.json               who it is: schemaVersion, id, name, role, avatar, color,
│                            workdir (only when it is a folder of the user's), folders, defaults
├─ SOUL.md  MEMORY.md  memory/<topic>.md
├─ sources/<id>.md           first-hand text, verbatim after YAML front-matter
│                            (title, sourceUrl, version, fetchedAt, subject, createdAt)
├─ sources/<id>.pdf          a first-hand PDF, unchanged
├─ sources/<id>.pdf.yaml     its sidecar (title, sourceUrl, version, fetchedAt,
│                            subject, pages), plain YAML
├─ guides/<id>.md            the mentor's own guides (title, subject; never sourceUrl)
├─ courses/<id>.yaml         the course JSON as YAML; lesson files relative to the folder
├─ notes/<id>.md             title, slug, tags, createdAt, updatedAt, sourceSession
│  notes/assets/<id>/        the pictures that note shows, linked relatively
├─ canvases/<id>.excalidraw  Excalidraw files, with a `loci` key for title and tags
└─ repos/  lab/              cloned source and experiments; never indexed or watched
```

The code is in `src-tauri/src/mentor_store/`: `paths.rs` (the root, names, NFC ids, paths that cannot leave the folder), `format.rs` (the formats; unknown keys are kept on rewrite, a newer `schemaVersion` is read and never rewritten), `fsio.rs` (atomic writes), `index.rs`, `registry.rs`, `migrate.rs`, `watch.rs`, `bundle.rs` (export and import) and `commands.rs`.

- **Rust owns the files.** The commands the window always called (`agent_documents_*`, `course_*`, `notes_*`, `canvas_*`, `agent_load/read/save`) keep their names and payloads. For a mentor whose content is in its folder they read and write files; for anything else (a note with no mentor, a project canvas, a mentor not migrated yet) they use the tables as before. A read re-checks its file, so an edit made outside the app is what the next read shows.
- **Mentors may edit their files.** The tool guide says so; `library.check` lists files that could not be read and why. Soul and memory still change only through `soul.*` and `memory.*`, which date, redact and archive.
- **Conflicts.** Editors name the hash they read. A note saved over a file that changed on disk keeps the disk version beside it as `notes/<id>.conflict-<time>.md`; Soul and memory refuse with `conflict`; a canvas refuses a stale revision. When the open note changes on disk, the editor follows it silently if it has no unsaved edits, and otherwise shows a one-line bar, **Changed on disk — Reload · Keep mine**: Reload takes the disk version, Keep mine saves the editor's text with the disk version kept as the conflict copy. An open canvas reloads a scene changed on disk when it has no pending local change. Whole-document writes by id from the mentor (`courses.write`, `documents.write`) replace, as they always have.
- **The index.** `mentor_content` has one row per content file (title, metadata, text of sources, guides and notes, the course JSON, the scene), with its hash, size and time; `mentor_content_fts` is a trigram FTS5 index for search in any script. Listing never touches the disk. At start, and when a folder is newly watched, each mentor's five content folders are walked and only changed files re-read. A file that stops parsing keeps its last good row and gains an `error`.
- **PDF sources.** A PDF is indexed through its sidecar (`mentor_store/pdf.rs`): the sidecar supplies the title and address, and the PDF's text is extracted locally with `pdf-extract` (pure Rust, no network) into the row's body, so `library search` and `documents.read` have the paper's words; the page count comes from the PDF. Either file changing re-reads the pair. A PDF without a sidecar is not a source yet, and a sidecar without its PDF keeps its row with an `error`; `library check` names both. The reader opens the PDF in `FilePane`, so highlights, notes and page links work as on any other PDF.
- **The watcher.** `watch.rs` follows the root, each mentor folder, its content folders and `memory/`, each non-recursively (FSEvents on macOS). Changes settle for 200 ms, are indexed, and reach every window as `loci:mentor-content-changed`, which `mentorStore.ts` turns into the refresh events the UI already listens to. The app's own writes are indexed when made, so their echo reports nothing.
- **The roster.** `mentors` holds the half of the roster that is not portable (conversation id, rail position, local flags) and each mentor's folder. `features/agents/model/mentorStore.ts` loads it at boot and sends every change; localStorage keeps a copy, so `listAgents()` stays synchronous and an older Loci still finds the roster. A new mentor gets a folder named like 0.3 workdirs, which follows its name until it is first used. Removing a mentor renames `mentor.json` to `mentor.removed.json` and keeps the folder; a folder with `mentor.json` copied into the root is adopted.
- **Defaults.** `mentor.json` `defaults` keeps the chat's provider, model, effort and permission mode; the window updates them whenever the mentor's chat changes any of them. Every new conversation of that mentor starts from them, including a reset, a mentor just imported, and the empty conversation a command made that was released again instead of saved. The stored model id is kept even before its provider's catalog has loaded.
- **A workdir of the user's** stays where it is: the mentor's content goes into its own folder in the root, and `mentor.json` names the workdir. The app never writes content into a folder the user chose.

### Tables

| Table | Rust module | Holds |
| --- | --- | --- |
| `sessions`, `in_flight_sessions` | `session_store.rs` | session transcripts, and which sessions were still running at quit |
| `agent_transcript_pages` | `agent_transcript.rs` | older turns of an agent's conversation, moved out of its session |
| `mentors`, `mentor_content`, `mentor_content_fts`, `lesson_progress`, `mentor_state` | `mentor_store/` | the registry, the index of mentor folders and its full-text index, course progress (no foreign key, so it outlives a file's brief absence), view state |
| `learning_sources`, `reading_documents`, `pdf_annotations` | `learning.rs` | source references, PDF identities and every reader's marks (a mark on a file in a mentor's folder is keyed `mentorFile` `<agent>/<path in the folder>`, so it follows the folder) |
| `canvas_checkpoints` | `canvas.rs` | the checkpoint ids agents continue drawing from |
| `notes`, `canvases` | `notes.rs`, `canvas.rs` | notes with no mentor and project canvases; 0.3 rows of mentors, kept as they were |
| `agent_documents`, `courses`, `course_progress` | | 0.3 data, kept unchanged since the migration; read only for a mentor not migrated yet |
| `workspace_snapshot`, `feed_item_state`, `session_reminders`, `learning_widgets` | | tables of removed features; no longer read or written |
| `schema_migrations` | `session_store.rs` | the baseline version, and `40` once 0.3 data is in mentor folders |

Habits stay in `<app data>/agents/<id>/habits.json`: they run on their own, and a folder imported from elsewhere must not bring jobs.

Tables are created on demand with `CREATE TABLE IF NOT EXISTS`. There is no migration framework, so a change to an existing table has to keep reading databases written by older versions.

### From 0.3

At start the window hands its 0.3 roster and view state to `storage_migrate` (`loci storage migrate --dry-run` reports without writing). Before the first real run it copies `loci.db` (`VACUUM INTO`), `agents/` and the roster to `<app data>/backups/v0.4-migration-<time>/`. Each mentor's documents, courses, notes, canvases, Soul and memory are written into its folder, and its progress into `lesson_progress`; old rows, old files, localStorage keys and the user's folders are not changed. A file already holding the same text is done; one holding other text is kept, and the 0.3 version goes beside it as `<id>.from-0.3.<ext>`. A mentor is marked migrated only when all of its files are written, so an interrupted run resumes; a mentor that fails keeps using the old tables and the others go on. The same pass runs at every start: rows an older Loci changed after a downgrade come back as files (or `.from-0.3` copies), and a mentor it added is migrated.

Downgrading to 0.3 works: it reads the old tables (as they were at migration) and the roster copy in localStorage. Content written by 0.4 is in the folders, which 0.3 does not read.

Workspace reset clears the tables and app data as before and forgets every mentor; their folders stay, and `loci mentors import --folder` brings one back.

### Export and import

`bundle.rs` zips a mentor's folder (without `repos/` and `lab/` unless asked) with a `manifest.json` (format `loci-mentor`, each file's SHA-256, the repositories with their remote and commit) and `.loci-state/state.json` (progress, marks on its documents and files, view state). Import checks every path and hash, refuses links and archives over 2 GB, extracts into a new folder in the root and gives the mentor a new id when the install already has one with its id. Conversations are not exported.

Loci reads Cursor's own store to recover sub-agent activity its ACP stream omits (`cursor_store.rs`), and writes none of it.

## The control channel

`control.rs` is an authenticated loopback transport. Windows own execution; a caller never receives arbitrary Tauri command access or direct database write access.

1. When a turn starts, Loci gives that session a grant: an endpoint and a token, passed to the agent process as `LOCI_APP_ENDPOINT` and `LOCI_APP_TOKEN`. Credentials travel by environment variable and never appear on a command line.
2. The grant works only while that turn is active.
3. Requests are routed by namespace, and each namespace has its own rule:

| Namespace | Used by | Rule |
| --- | --- | --- |
| `app` | agents, through the `app` subcommand of the desktop executable (`control_cli.rs`) | an agent's conversation and its habit runs always have access |
| `canvas` | the built-in Excalidraw server | every session may draw while the switch in **Settings → MCP** is on, only in its own project |
| `cli` | `loci <noun> <verb>` from a terminal outside Loci (`external_cli.rs`) | the local token in `<app data>/control/cli-token`, while **Settings → General → Command line** is on |

The `cli` namespace is not tied to a turn. A running Loci writes where it listens to `<app data>/control/endpoint.json` and keeps a token in `cli-token` beside it, both readable only by the user (`cli_access.rs`). The token is the only credential that opens `cli`, and it opens nothing else. The host answers `status` and the token commands itself. Every other command goes to the main window, or to the first window whose listener is up; when none is, the main window is shown or opened. Each build has its own data folder, so `loci --app <identifier>` reaches Loci Dev or a QA build and never the installed app by accident. See [cli.md](cli.md).

The switch is read when a turn starts and kept for that turn, so a change applies from the next turn and a running turn can finish. A provider may start its process under a generation-scoped id (`<session>#<n>`, as Antigravity does); the credential is looked up by the session that owns the process.

## Built-in MCP servers

One stdio MCP server ships in `src-tauri/resources` and runs on the user's Node.js (20.11+) or Bun, located by `canvas_mcp.rs`.

- **`excalidraw-mcp/`** runs the official Excalidraw MCP server unmodified (`official/`; origin, version and hashes are in the `SOURCE` file beside it) behind `loci-bridge.mjs`, which swaps the official checkpoint store for Loci's canvases and adds tools to read canvases and update elements by id. To update the vendored server run `node scripts/vendor-excalidraw-mcp.mjs`. See [canvas-mcp.md](canvas-mcp.md).

Claude Code receives it through `--mcp-config`, Codex through `-c mcp_servers.*` overrides. It can be turned off in **Settings → MCP**.

### Agent CLIs that cannot be given an MCP server

Antigravity and Pi offer no way to attach an MCP server to one session without editing the user's own configuration, so they reach the same server through the desktop executable (`control_cli.rs`):

```sh
loci canvas create_view --input drawing.json
loci canvas --help
```

One call asks the running app which command starts the server (the reserved `mcp.server` request, answered by `control.rs` under the namespace's own rule), starts that server, makes the MCP handshake, calls the one tool and prints its text. The server is the same process an MCP client would attach, so the tools, their descriptions, the save receipts and every rule in the window are identical. Only the tools agents are given are accepted; the official widget's private tools stay out of reach.

What differs is how the agent finds out and how it is asked:

- **Knowing.** `useSessionSubmission.ts` appends a note to a turn: `<loci_canvas>` once per provider conversation while the switch is on. The harnesses that work this way are listed in `features/sessions/model/builtinCli.ts`.
- **Asking.** A provider that asks before running a command (Antigravity) sends the command with the request. `builtinCliCall` recognizes it only when it is exactly one tool call of this app's own executable, with nothing a shell would expand, chain or redirect; `builtinCliDecision` then answers with the rules of the MCP tools. Anything else is an ordinary command request. Pi never asks, and in Plan mode it has no shell, so the tools are out of reach there.
- **Showing.** The transcript names such a shell row as the canvas call it is (`canvasToolCall.ts`).

A new provider that can run shell commands needs an entry in that list, and an approval branch like Antigravity's if it asks before running commands.

## Agents

An agent, shown to the user as a mentor, is long-lived and belongs to no project: a name, a Bottts robot avatar in its own color, one conversation that never ends, and a working folder of its own. Each one has a face on the mentor rail. The code is in `src/features/agents`, with the wiring in `src/app/hooks/useAgents.ts`, `useAgentHabits.ts` and `useAgentDelegation.ts`.

- **Roster.** `model/agent.ts` reads the agents from a localStorage copy (`loci:agent-roster`) of the registry and `mentor.json` files (see [Mentor folders](#mentor-folders)). An agent's conversation is an ordinary session whose permission mode starts at the default for new mentors, Full access unless changed in Settings → Your mentors. A saved conversation from before that default switches to Full access once, when the mentor is next opened; `accessMigrated` on the roster records the switch, so a mode later chosen in the mentor's settings, its composer or through the app CLI is kept. Habit runs keep their own access (`auto` by request, otherwise Full access) and the sessions a mentor starts through the app CLI inherit its mode. The `projects` key is still read and written for older agents; those folders are shown as "other folders" the agent may use, not as projects. The conversation is shown in the conversation column of its workspace.
- **Workdir.** Each agent has a working folder the user can see (`Agent.workdir`, `model/agentWorkdir.ts`): cloned source under `repos/`, experiments under `lab/`. It is the mentor's own folder, `~/Loci/<slug>` (`~/Loci-Dev/<slug>` for Loci Dev, so development never writes into the real folder), where the slug comes from the agent's name and falls back to `mentor-<id>`. `agent_workdir_create` (`agent.rs`) only ever makes a new, empty folder: if the name is taken it tries `<slug>-2`, `-3`, and so on. The user can point an agent at any existing folder in its settings; `agent_workdir_ensure` uses such a folder as it is and creates nothing in it. The app never moves or deletes files there. A new conversation, and a conversation started by Reset, runs in the workdir. A saved conversation keeps the folder it started in, because the CLIs tie a resumable conversation to it: older agents keep running in the home folder, which already holds the default workdir, and move into it on their next reset. The workdir is not treated as a project (no project-location sync, notes are not filed under it). `ui/AgentFilesSection.tsx` lists the workdir and the other folders with the shared file tree; it is the Files segment of the mentor's library, where the library's filter drives the tree's file search and the tree's folder actions (new file or folder, import, refresh, collapse all, hidden files, reveal) sit in one "…" menu.
- **Files.** `agent.rs` keeps `SOUL.md`, `MEMORY.md` and `memory/<topic>.md` in the mentor's folder (in `<app data>/agents/<id>/` until it is migrated) and `habits.json` in `<app data>/agents/<id>/`. The folder is not a repository; cloned source lives in its `repos/`, each a repository of its own, so a pull request there cannot reach the Soul. Paths are checked against that short list, writes are atomic and owner-only, and a save names the hash it read, so the user and the agent cannot overwrite each other. The same check is how two windows avoid running one habit twice.
- **What a turn carries.** `model/agentFiles.ts` wraps the visible Soul and factual identity (name, role, `workdir` and other `folders`) and memory in `<loci_context>`. A short tool guide introduces courses, documents, notes, drawings, memory, Soul, habits and reply formats, alongside the command and help entry point. Teaching style and standing behavior remain defined by the user and the Soul; the tool guide does not direct session creation or delegation. A provider conversation receives its Soul once and memory when it changes; `planAgentContext` records the provider conversation and file hashes. Format references are available explicitly through `app --help` from `src-tauri/resources/app-formats.md`.
- **Rotation.** At 80% of the reported context window an agent starts a fresh provider conversation, carrying factual excerpts of the last two exchanges and one line for each earlier exchange. The full transcript stays readable in the chat. `prepareAppTurn` also replaces old agent and ordinary provider conversations once to remove previously injected global policies. Edits retain their provider and defer that cleanup; a model switch to a fresh provider completes it. This migration uses the existing context receipt and rotation store, without a database migration.
- **Paging.** The transcript itself would also grow without bound. Past 60 turns an idle chat that is not in view moves its oldest turns, down to 40, into `agent_transcript_pages` (`agent_transcript.rs`, `model/agentTranscript.ts`). The page is written before the session is trimmed and is keyed by its first block, so a crash in between archives nothing twice. The view offers the pages back with "Show archived history", above the transcript's own window of recent turns, and the agent's own `sessions.read` reaches into them. Pages are deleted with their session.
- **The app CLI.** An agent's conversation has `app` access in every turn, plus actions an ordinary thread does not have: `soul.*`, `memory.*`, `documents.*`, `habits.*`, `sessions.stop`, `sessions.archive`, `sessions.delete`, and `"project"` on the session and canvas actions, limited to its workdir and the other folders on its roster. Memory is changed only through the CLI, which dates entries, redacts common credential formats and moves old entries to an archive once `MEMORY.md` passes what loads into a turn.
- **Progress.** While a mentor's turn runs, `model/turnProgress.ts` turns its tool calls into one plain line each: saving a source or guide, cloning a repository, fetching a page, writing a course, reading a file. `ui/TurnProgress.tsx` shows the newest three under the turn's status line, expandable; the conversation header names the newest one in the same words, and `mentors turn` and `mentors send --wait --stream` expose the same entries to a terminal. An adapter that reports no tool calls leaves the spinner and "Working". The library marks a source, guide, course or note saved during the turn as New (`mentor/model/libraryNovelty.ts`) until the learner opens it or the turn ends.
- **Questions.** The Soul and current user request determine questioning behavior. CLIs can use their native question tool or emit a fenced `loci-question` JSON block; `features/sessions/model/standingQuestion.ts` renders it as a form. Such a question is standing: no provider request waits on it, so it outlives its turn and a restart, and the choice goes out as the next user message. This works in every session. The application does not set question counts or require a profile interview.
- **Cards.** A card is a fenced block in a reply that `features/sessions/ui/AgentMarkdown.tsx` draws as something better than code: `loci-question` (a form), `loci-document`, `loci-todo`, `loci-mindmap`, `loci-canvas`, and `mermaid`. Parsing is in `features/sessions/model/cards.ts`; components are in `ui/cards/` and `features/learning/ui/`. Any agent CLI can produce the text format. A card in a message that is folded into the turn's work stays in view (`cardsOnly`). A ticked checklist item bubbles a `loci-card-reply` event that `SessionPane` submits as the user's next message.
- **Library.** As soon as a message of an agent's conversation is complete, `useAgents.ts` saves its `loci-document` blocks (and `useSessionSubmission.ts` does so again when the turn ends) into its folder (`agent_documents.rs`): `sources/<id>.md` or `guides/<id>.md`, so writing the same id again revises it. There are two kinds: first-hand **sources** taken in verbatim from a file by `documents.write` (with `source_url`), and the mentor's own **guides** (`loci-document` blocks and `guides.write`, without). A source may be a PDF instead of Markdown: `documents.write` copies it in as `sources/<id>.pdf` with a `sources/<id>.pdf.yaml` sidecar, and its row lists in Sources with a PDF icon and its page count. Rows carry `kind` when read; one kind is refused over the other's id. A Markdown document opens in its reader (`ui/AgentDocumentReader.tsx`) and can be saved as an agent-owned note; a PDF source opens in `FilePane`, the PDF reader, at a page when a link names one. The agent reads its library back with `documents.list` and `documents.read`, and writes a guide from a file with `guides.write`. A canvas an agent draws without naming a project is in its library too: `canvases/<id>.excalidraw`, shown with `loci-agent://<id>` (`agentCanvasScope`) where a project path would be, so both the drawing tools and `canvas.*` work for an agent that has no project. Deleting an agent forgets it and its conversation; its folder stays on disk.
- **Creation.** The plus beside Agents directly opens a blank agent, without starting a model. New agents carry the editable default Soul and factual identity, with no hidden initialization or automatic naming instructions. The user's first message supplies the purpose or task. Model and effort controls sit beneath the agent composer; profile and permission controls live in the settings dialog. Existing agents keep their own Soul.
- **Window headers.** On macOS the mentor workspace's title bar shares the native 40px titlebar; when the rail is collapsed it starts with room for the window's buttons and a Back button. The reader's and the conversation's own headers sit below it. `shared/ui/PaneHeader.tsx` and `shared/ui/ResourceHeader.tsx` provide those headers for agents, conversations, documents, courses, canvases and files.
- **Courses.** Courses are scoped by agent and saved through `courses.write`; a stable course/lesson ID retains reading progress across revisions. Reading courses point to saved documents or local files and PDF pages. They open in the mentor's reader. The library's Courses segment (`mentor/ui/LibraryCourses.tsx`) shows one course at a time: a switcher whose menu lists the mentor's courses and ends with asking the mentor for a new one (a sentence started in the composer, not sent), the read count, a Continue card for the lesson `nextLesson` (`mentor/model/libraryCourse.ts`) suggests, and the outline (`mentor/ui/LibraryOutline.tsx`), which marks the open lesson and keeps it in view, ticks read lessons, half-fills begun ones and folds chapters (a wholly read chapter starts folded). Picking a course in the switcher opens it at that lesson. The reader's own outline is `learning/ui/CourseOutline.tsx`. The order is only a suggestion; there are no gates. Questions go to the owning agent conversation. Teaching style stays in the Soul.
- **Mentor workspace and settings.** `features/mentor/ui/MentorWorkspace.tsx` shows one agent as three columns with no title bar of their own: each column's 40px header is the window's top row (the library's segments and its fold button; the reader's page title with its actions, plus the library and Chat buttons once those columns are folded; the conversation's name, status, settings and ✕). The library on the left (`MentorLibrary`: four segments, one shown at a time, the chosen one a labelled pill and the others icons: Courses, Sources, Notes with the mentor's drawings, and Files, the mentor's working folder; Sources, Notes and Files have a filter for that list only, and arrow keys move between segments and rows), the reader in the middle (`MentorReader`) and the conversation on the right. Opening anything replaces what the reader showed; Close empties it. The left and right columns can be hidden and resized, and narrow windows lay them over the reader. `app/hooks/useMentorView.ts` keeps each agent's columns, the library's segment and course, and the page it was reading (identifiers only, plus the lesson in a course; the library's filter lasts for the window only) in `localStorage` under the same key the earlier overview used (mirrored into `mentor_state`), so coming back to a mentor, or restarting, reopens the lesson; a remembered page that has since been removed leaves the reader empty. Habits keep running but have no place in the library. General, Soul and editable Memory live in a separate settings dialog with left navigation, grouped properties and an avatar/color popover. Agent replies use quiet prose with a speaker signature and compact course/document chips, while ordinary sessions retain their existing layout preferences.
- **Agent notes.** Notes created from the library, a document reader or the agent CLI belong to their mentor: `notes/<id>.md` in its folder (0.3 notes carry `notes.agent_id`). A mentor note's pictures live in `notes/assets/<id>/` and are linked relative to the note; pictures still in `<app data>/note-assets/<id>/` are copied beside the note at start (the originals stay), and the note's copy travels in an export. The association does not depend on the current conversation ID. Notes without an agent association (written before agents owned notes) are found with ⌘K and open in the open mentor's reader without being reassigned. The nullable column is added to older databases without changing their content. Note editors share one save queue; opening something else waits for pending edits and stays on the editor if saving fails.
- **Habits.** `useAgentHabits.ts` checks every minute while the app is open. A due habit runs in a hidden session (`ephemeral`: never saved, never shown, never counted) with full access, because nobody is watching it. With Codex the run uses an ephemeral thread, so it leaves nothing in the user's own Codex history; other CLIs keep whatever record they normally keep. Its last reply is posted to the agent's chat, or nothing when the reply is `NOTHING_TO_REPORT`. An approval the run asks for is put to the user in the agent's chat and the answer routed back. A run may work for an hour; one that came due more than two hours ago is skipped rather than caught up; one runs at a time.
- **Delegation.** A session an agent starts reports back by default. The ones started in the same agent turn form a group (`model/agentSessionCompletion.ts`); when that turn has ended and all of them have stopped, the agent is sent their results as one new turn, once it is idle and the user has nothing queued (`useAgentDelegation.ts`). Reports waiting to be delivered live in memory only, so they do not survive a restart.

Everything an agent can reach goes through the same control channel and the same window-side handlers as its `app` CLI. The terminal's `loci` reaches the same handlers: a library command for a mentor (`loci courses write --mentor M`) runs the `app` action as that mentor's own conversation would. Widening what agents can do deserves the same care as any other change there. `sessions.delete` asks the user to confirm; an agent cannot remove a conversation on its own.

## The command layer

`src/app/commands` defines every command of the `loci` command line once: its name, its fields, who may call it (a terminal, a mentor's own turn, or both) and the function it runs. That function is the one the UI calls (`useAgents.create`, `mentorView.show`, `setLessonStatus`, the composer's `changeModel`, ...). `useCommandContext.ts` gives commands the window's hooks, and `useAppControl.ts` routes `cli` requests, and mentors' `reader.*` requests, to them. `npm run gen:cli` writes `src-tauri/resources/cli-commands.json` from the definitions. The Rust client reads it to parse arguments and print help without the app, and a test keeps it current. A new feature adds its command in the same place.

## Links between objects

Replies can link to notes (`loci://note/<id>`), canvases (`loci://canvas/<id>`), registered sources (`loci://source/<id>`), sessions and files. `shared/lib/appResourceLinks.ts` parses and builds them; the chat sanitizer allows only the `loci` scheme beyond its defaults, and checks resource kinds and ids before URL normalization. Links are handled by the current window and are not registered with the operating system.

## Platform code

- macOS: `macos.rs` (window chrome and background blur), notifications through `UNUserNotificationCenter`.
- Windows: `windows.rs` (job object so child processes die with the app), `tray.rs` (the way back to a window that closing hid).
- Linux: notifications through `notify-rust`, Wayland-aware clipboard reads.
- `src-tauri/tauri.conf.json` is the base configuration. Tauri merges `tauri.linux.conf.json` or `tauri.windows.conf.json` over it. `tauri.stable.conf.json` is only for `npm run tauri:stable`; `tauri.dev.conf.json` makes a release build of Loci Dev (`script/build_and_run.sh`); `tauri.release.conf.json` adds the signed update artifacts the release workflow uploads. Debug builds always run as Loci Dev (`src-tauri/src/flavor.rs`), and only the installed app registers the updater ([releasing.md](releasing.md)).

## Network and trust boundaries

- The WebView has a strict Content Security Policy (`'self'` for scripts, no remote frames) and the asset protocol is scoped to the app data folder. Frames are disabled by `frame-src 'none'`.
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
