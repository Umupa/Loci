# Changelog

All notable changes to Loci are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). While the major version is 0, a minor release may include breaking changes.

## [Unreleased]

Nothing has been tagged yet; the first release will be 0.1.0. Until then this section lists what the first release will contain.

### Added

- Code-step and concept-navigation courses with saved learning progress, inline diffs, concept-map navigation and teaching agent templates.

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
- **Interactive explanations** in every conversation: self-contained `loci-widget` HTML/CSS/JavaScript/SVG cards with inline and expanded views, shared interaction state, source links, editable follow-up drafts, and manual Keep in Library. Generated content runs inside a sandboxed iframe behind a fixed local proxy; it has no network or native-command API. The same widget id revises an explanation while preserving its retention and state.
- **Source-backed PDF reading**: selectable passages can prepare a question with page anchors or become local highlights with editable notes and linked discussions. Anchors span lines and pages and follow zoom. Moved documents can be relocated after checking their PDF fingerprint; image-only pages require a text version because OCR is not included. Web sources accept a URL and pasted excerpt, and conversation excerpts can link back to their messages.
- **An agent's library**: documents an agent writes open beside the chat, are kept under Details → Library grouped by subject, are revised by writing them again under the same id, and can be saved as notes. The agent reads them back with `app documents.list` and `documents.read`. Canvases an agent draws are kept in its library as well, so an agent with no project can draw.
- **Agent creation**: the plus beside Agents offers a blank agent or the Tutor template. Both open directly into chat using the default model. One natural sentence can define the new agent's job; it chooses a short name, role and initial Soul while starting useful work. Profile fields and preferences do not block the first task. One-off requests do not become permanent roles, and user-chosen names and custom Souls are preserved. The Tutor template can be rewritten or reset under Settings → Your agents.
- The Tutor template starts with a lesson or exercise, learns preferences through use, keeps progress in memory, and teaches with documents, mind maps and checklists. Roadmaps follow when the learner wants to continue. This replaces the `/learn` skill that was in development; learning maps it created remain as ordinary canvases.

### Changed

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

[Unreleased]: https://github.com/Umupa/Loci/commits/main
