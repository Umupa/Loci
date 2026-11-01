# Changelog

All notable changes to Loci are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). While the major version is 0, a minor release may include breaking changes.

## [Unreleased]

### Added

- **Read with your mentor.** Selecting text in any reader (lessons, sources, notes, Markdown and code files, PDFs) offers **Ask (your mentor) · Highlight · Note**. Highlights and notes work in every reader, follow small edits to the text, and are listed under "Highlights & notes"; a passage whose words are gone is kept and marked as changed. Your mentor knows the heading and paragraph you are reading and what you selected, and its replies link to the exact passage, which opens in the reader and flashes.
- **A new left column.** Four icons at the top (Courses, Sources, Notes, Files) show one list at a time; the chosen one opens into a labelled pill. Courses has a course switcher with your progress and an outline that reads like a table of contents and follows the reader, with highlight counts per lesson. Each mentor remembers its segment.
- **Reading type.** Reader text is set at 15/26 in a measured column. Settings → Appearance → Fonts → Reading font switches it to a serif (with Chinese serif fallbacks); the interface stays sans.
- **Code reads like a source.** Code files and code lessons have syntax highlighting and line numbers; highlights and line links still land.
- **The `loci` command line.** Drive a running Loci from any terminal: mentors (create, settings, send a message and wait for or stream the reply), sources and guides, courses and lesson status, notes, canvases, the mentor's files, highlights, the reader and the library, sessions, soul and memory, models, updates and a few settings. Output is JSON. `--app` targets Loci Dev or a test build. Settings → General → Command line turns it off, rotates its token, or installs `loci` into `~/.local/bin`. Agents outside Loci, such as Claude Code in a terminal, can use it to act as a mentor.
- **Mentor guides.** A mentor's own reading guides and briefs are kept apart from first-hand sources: listed under "Mentor's guides" and labelled in the reader.
- **Rewritten Mentor and Lens templates.** New mentors ask at most one question before you are reading, reply in the language you write in, save sources verbatim and pinned to a version or commit, keep a first course to 6–12 lessons, and cite clickable passages. Lens hands you the course first, starting with the project's own README and design docs. A mentor's Soul page has **Replace with template…** to move an existing mentor to the new template.
- **An in-app update prompt.** Release notes are formatted and scroll inside the dialog, with Later and Install always visible, a progress bar, and Retry on failure. Automatic checks only put a dot beside Settings.

### Changed

- **One header row.** The separate title bar and breadcrumb are gone: each column's header is the window's top row. The library's toggle sits at the end of its header, the conversation has its own ✕, and once either is folded its button moves into the reader's header.
- **Mentors start in Full access** and stop asking before every command. Existing mentors switch once; a mode you choose afterwards sticks. Settings → Your mentors sets the default for new mentors.
- A quieter, more consistent interface: one accent used sparingly, one highlighter colour for what you marked, neutral chapter marks, sentence-case labels, one type scale, line icons instead of sparkles, and fewer looping animations. The composer mascot is off unless you turn it on.
- Every mentor opens with a learning greeting. Settings, the gallery and confirmations say "mentor" and no longer mention projects.
- File links in replies accept `#L12-40` as well as `#L12-L40`, and `#p7` opens a PDF at that page.
- Grok Build conversations use the model the `grok` CLI reports as its default, list all its models, and show the CLI's own error when a turn fails.
- Keyboard and screen readers: focus stays inside dialogs and returns to what opened them; the mentor rail, ⌘K search, settings tabs and lists answer the arrow keys; Escape closes the reader from anywhere except a text field.

### Fixed

- Selecting "Ask" while the conversation is folded now opens it with your draft.
- Opening a lesson starts at its top and no longer marks it read on arrival.
- Unsaved file edits, typed highlight notes and a Soul that failed to save are no longer lost; quitting with unsaved files asks first. Deleting a note, a highlight or a source asks first.
- Renaming or trashing the file you are reading keeps the reader in step.
- The reader keeps at least 360 px when columns are resized or the window shrinks, and on narrow windows the library folds away after a choice.
- A conversation opened in the reader has a close button; approval prompts no longer cover the title bar; Windows and Linux keep their window buttons with no mentor open.
- Holding ⌘W no longer closes the window, and Ctrl+W/Ctrl+T on macOS are left to text editing.
- Settings → MCP and the provider defaults are global (no empty project pickers); personal skills are labelled personal; the Chinese Settings no longer mix in English words.
- Many smaller layout, contrast and copy fixes from a full UI review.

Nothing in your data is deleted: existing mentors keep their Soul, conversations and library.

## [0.2.0] - 2026-10-31

### Added

- **A mentor for each topic.** The rail on the left lists your mentors. Create one with **+** (or ⌘T) from the Mentor or Lens template, or start a blank one. With no mentors yet, Loci shows how to create the first.
- **A three-column workspace.** On the left are the outline of the open course and the mentor's library: Courses, Sources, Notes, Canvases and Files. The reader is in the middle and the conversation is on the right. Opening a lesson, source, note, canvas, file, PDF or a session the mentor started replaces what the reader shows. The title bar shows mentor › course › lesson. ⌘B folds the library and ⇧⌘B the conversation.
- **Back where you left off.** Switching back to a mentor, or restarting Loci, reopens the lesson or page it was showing.
- **A working folder per mentor.** It is `~/Loci/<name>`, made the first time it is needed, and holds cloned source code and experiments. Mentors know where it is, and its files appear under Files in the library. In the mentor's settings you can reveal it or point it at a folder you already have; nothing in that folder is changed. The Mentor and Lens templates clone repositories there instead of into the shared `~/Loci/repos`.
- **⌘K search** across your mentors and the titles of their courses, lessons, sources, notes and canvases, plus your conversations with them.
- **Shortcuts:** ⌘1–9 and ⇧⌘[ / ] switch mentors, and ⌘W closes the reader (or the window when the reader is empty).

### Changed

- New mentors, and mentors whose conversation you reset, run in their working folder. Existing conversations keep running where they started, so they resume as before.
- Folders you gave a mentor before are listed as "Other folders" instead of projects.
- Settings call them mentors (导师) throughout.
- Loci is now an AI-native learning workspace for engineers: one resident mentor per topic, which gathers first-hand sources and reads them with you. The README, the app description and [docs/roadmap.md](docs/roadmap.md) describe the new direction. Claude Code and Codex are the supported agent CLIs; the other eight are experimental.
- Scheduled habit runs get app access through an internal turn option instead of a `/operator` prompt. Prompt text can no longer grant app access.

### Removed

- Usage meters, account switching and the Accounts and "Usage and privacy" settings. The notice shown when a CLI reports that its usage limit was hit stays, and sessions that already use a saved account keep working.
- Session reminders, session folders, `/add-to-folder` (and the agent `folders.list` / `folders.move` actions), and session filters in the sidebar, including "Show archived in the sidebar".
- The `/operator` command.
- The Ledger market-briefing template. Agents already created from it keep their Soul.
- The welcome animations, the send accent and the turn celebration sparkles.
- Per-project chat backgrounds and per-project notification settings. The global background, wallpapers, themes and project mutes stay.
- Tabs, split panes, the project rail and the session sidebar, with their menu items and shortcuts. Project logos, colors and mascots go with them; mentors keep their own avatars.
- The global Courses, Notes and Search pages, and Settings → Archive. Courses, notes and canvases live in each mentor's library, and notes from before mentors owned notes are found with ⌘K.
- Conversations that do not belong to a mentor are no longer listed. They stay on disk, and sessions a mentor starts still open in its reader.

Nothing is deleted from your data: tables and settings that these features used, including the saved tab layout, are left in place, unread. Shortcuts you had rebound for removed commands are ignored.

## [0.1.1] - 2026-10-31

### Changed

- A new app icon: a corridor of archways ending in a lit door, after the memory palace Loci is named for. Loci Dev has the same door on orange, marked DEV, so the two are easy to tell apart in the Dock.

## [0.1.0] - 2026-10-31

### Added

- **Courses read from first-hand sources**: a course is chapters of lessons, each pointing at a source to read (a document in the agent's library, optionally from one of its headings, or a PDF and its pages) with saved reading progress. The course holds no text written by the agent. The Navigator template agrees a plan with you before collecting anything, then takes official documentation, specifications and papers into its library with `app documents.write`, which reads the text from a file the agent saved so it is never retyped by a model. A source records where it was published, shows that page's pictures, and cannot be revised by a reply. Selecting text in any library document adds the passage to the agent's chat.
- Code-step courses with inline diffs, and the Builder and Lens agent templates.

- Simplified Chinese Settings with system language detection and instant switching. The workspace, menus and notifications remain in English.
- Desktop shell for agent CLIs: projects as local folders, sessions through Claude Code, Codex, Cursor, Grok Build, OpenCode, Pi, omp, fx, Hermes Agent and Antigravity, model and permission selection, agent questions, plan and task display, tabs and drag-to-split panes, session folders, ⌘K search, attachments, reminders and desktop notifications.
- Markdown notes with `@` mentions, and Excalidraw canvases.
- 22 Omarchy color themes with matching code highlighting, 72 bundled wallpapers, and configurable code and interface fonts.
- Built-in `loci_excalidraw` MCP server for Claude Code and Codex: the official Excalidraw MCP server, unmodified, writing into Loci's canvas store, with exact element updates by id and live panel updates.
- `/operator`, which lets an agent drive Loci itself over an authenticated loopback channel that is valid only during the turn it was enabled for.
- Links to notes, canvases, sessions and project files that open inside the app (`loci://note/<id>`, `loci://canvas/<id>`, session and file links with page and line ranges).
- The canvas tools for Antigravity and Pi. These agent CLIs cannot be given an MCP server for one session, so they call the same built-in server through Loci's own CLI (`loci canvas …`), with the same rules, the Excalidraw switch in Settings, and nothing to install or configure.
- `/btw`, `/draft`, `/compact`, `/mcp` and `/add-to-folder`.
- Markdown files show pictures stored beside them, and a link to lines of a Markdown file opens the section in the preview instead of the raw source.
- Project files for contributors: README in English and Chinese, a documentation index and architecture overview, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, issue and pull request templates, and GitHub Actions for checks, releases and dependency updates.

- Questions with choices stay until you answer them. A question an agent asks and then ends its turn on is no longer taken away seconds later; picking a choice sends it as your next message. Agent CLIs without a question tool can ask the same way, by ending a reply with a `loci-question` block.
- **Agents**: long-lived agents on the rail above the projects, each with a robot avatar, a name and a color, one conversation it returns to, and the projects it is given. An agent has standing instructions (`SOUL.md`) and a dated memory that carry across provider conversations, both editable in its Details panel and kept in the app's data folder. Its conversation reads like a messenger chat, with bubbles and a one-line input. It can run habits on a schedule while Loci is open, posting to its chat only when there is something to say, and can start sessions in its projects that report back together once they finish. Its conversation moves to a fresh provider conversation when the context is nearly full, without losing the chat.
- **Cards**: an agent's reply can carry a document, a checklist, a mind map or a link to a canvas, each written as a fenced block (`loci-document`, `loci-todo`, `loci-mindmap`, `loci-canvas`) that any agent CLI can produce, next to the question card and Mermaid diagrams. Ticking a checklist item sends the agent a message.
- **Source-backed PDF reading**: selectable passages can prepare a question with page anchors or become local highlights with editable notes and linked discussions. Anchors span lines and pages and follow zoom. Moved documents can be relocated after checking their PDF fingerprint; image-only pages require a text version because OCR is not included. Web sources accept a URL and pasted excerpt, and conversation excerpts can link back to their messages.
- **An agent's library**: documents an agent writes open beside the chat, are kept under Details → Library grouped by subject, are revised by writing them again under the same id, and can be saved as notes. The agent reads them back with `app documents.list` and `documents.read`. Canvases an agent draws are kept in its library as well, so an agent with no project can draw.
- **Agent creation**: the plus beside Agents offers a blank agent or a template. Both open directly into chat using the default model. A template writes its visible Soul into the new agent. Name, role, model and Soul are editable in Details; built-in templates can be rewritten or reset in Settings → Your agents.
- The Tutor template starts with a lesson or exercise, learns preferences through use, keeps progress in memory, and teaches with documents, mind maps and checklists. Roadmaps follow when the learner wants to continue. This replaces the `/learn` skill that was in development; learning maps it created remain as ordinary canvases.

- **Updates**: an installed Loci checks GitHub Releases a little after launch and every few hours, shows the new version's notes, and installs it and restarts when you agree. **Settings → General → About** checks on demand.
- **Loci Dev**: what you run from source has its own name, identifier (`com.loci.desktop.dev`) and data folder, so it runs beside an installed Loci without opening its database. `npm run install:local` installs this checkout as the real Loci on macOS.

### Changed

- Agent behavior comes from the user and visible Soul. Built-in templates use an ordered JSON catalog and separate Markdown bodies; global questioning, initialization, memory, delegation and presentation policies are removed. Format references are available through `app --help`. Existing provider conversations carrying old policies restart once with transcript excerpts, while their full chat remains visible.
- Agent inputs share the session composer's field, tool row and button styling, with modes beside the attachment menu and Send aligned to the right. Tool rows wrap within narrow panes.
- Agents offer Bottts robot avatars and the simpler Bottts Neutral faces, with a series picker. Existing avatar names and colors are preserved. Artwork is generated ahead of time and kept local; small avatars stay static, while compatible eyes blink in the visible Details preview and respect reduced motion.
- The README is now written in English; the Chinese version is `README.zh-CN.md`.

### Fixed

- Project file links in chat open in Loci's file pane, preserving line references and ranges. Opening in the system's default application remains available in the context menu.
- Settings now loads live provider catalogs even when fallback models are available.
- Codex turns omit collaboration overrides until a model is known, avoiding rejected requests.
- Notes created without a title finalize their slug when title editing ends; existing slugs stay stable.
- Max and Ultra effort animations now apply to every provider exposing those options.
- Native New Tab and Close Tab menu actions target the focused window.

### Removed

- The extraction plan and acceptance notes from `docs/`. They remain in git history.

[Unreleased]: https://github.com/Umupa/Loci/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Umupa/Loci/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/Umupa/Loci/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Umupa/Loci/releases/tag/v0.1.0
