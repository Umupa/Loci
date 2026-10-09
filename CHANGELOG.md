# Changelog

All notable changes to Loci are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). While the major version is 0, a minor release may include breaking changes.

## [Unreleased]

Nothing has been tagged yet; the first release will be 0.1.0. Until then this section lists what the first release will contain.

### Added

- Simplified Chinese Settings with system language detection and instant switching. The workspace, menus and notifications remain in English.
- Desktop shell for agent CLIs: projects as local folders, sessions through Claude Code, Codex, Cursor, Grok Build, OpenCode, Pi, omp, fx, Hermes Agent and Antigravity, model and permission selection, agent questions, plan and task display, tabs and drag-to-split panes, session folders, ⌘K search, attachments, reminders and desktop notifications.
- Markdown notes with `@` mentions, and Excalidraw canvases.
- 22 Omarchy color themes with matching code highlighting, 72 bundled wallpapers, and configurable code and interface fonts.
- Built-in `loci_excalidraw` MCP server for Claude Code and Codex: the official Excalidraw MCP server, unmodified, writing into Loci's canvas store, with exact element updates by id and live panel updates.
- `/operator`, which lets an agent drive Loci itself over an authenticated loopback channel that is valid only during the turn it was enabled for.
- Links to notes, canvases, sessions and project files that open inside the app (`loci://note/<id>`, `loci://canvas/<id>`, session and file links with page and line ranges).
- `/learn` for Claude Code and Codex: a learning map canvas that records a node as learned only from the learner's own words, checked by the app; revisits on a 1, 3, 7, 21, 60 and 150 day ladder with the map covered; judgment nodes with a look-back date; learning calls shown in the transcript.
- The canvas tools and `/learn` for Antigravity and Pi. These agent CLIs cannot be given an MCP server for one session, so they call the same built-in servers through Loci's own CLI (`loci canvas …`, `loci learn …`), with the same rules, the Excalidraw switch in Settings, and nothing to install or configure.
- `/btw`, `/draft`, `/compact`, `/mcp` and `/add-to-folder`.
- `/learn` sets a subject up before teaching: an overview of the field, an interview that becomes `profile.md` (goal, level, depth, language, how explanations land), a roadmap in `roadmap.md` whose stages and topics appear on the map as dashed nodes, and the reading for each topic gathered into `sources/` as complete texts in the learner's language. The agent does this with its own tools, as the skill's prompt describes.
- Markdown files show pictures stored beside them, and a link to lines of a Markdown file opens the section in the preview instead of the raw source.
- Project files for contributors: README in English and Chinese, a documentation index and architecture overview, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, issue and pull request templates, and GitHub Actions for checks, releases and dependency updates.

### Changed

- The README is now written in English; the Chinese version is `README.zh-CN.md`.

### Fixed

- Settings now loads live provider catalogs even when fallback models are available.
- Codex turns omit collaboration overrides until a model is known, avoiding rejected requests.
- Notes created without a title finalize their slug when title editing ends; existing slugs stay stable.
- Max and Ultra effort animations now apply to every provider exposing those options.
- Native New Tab and Close Tab menu actions target the focused window.

### Removed

- The extraction plan and acceptance notes from `docs/`. They remain in git history.

[Unreleased]: https://github.com/Umupa/Loci/commits/main
