# Changelog

All notable changes to Loci are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). While the major version is 0, a minor release may include breaking changes.

## [Unreleased]

## [0.8.9] - 2026-11-04

### Changed

- **A course's contents read as one ink line.** Each lesson is a dot on it, filled once read; the lesson open is the mentor's dot with its title highlighted. Lessons keep to one line and lose their numbers.
- **The translation menu shows each way of reading as a glyph**: 中 for the translation, Aa for the original, both stacked for side by side, inked when chosen. Asking for the rest carries the mentor's face.

### Fixed

- **A source opened from the library shows translation as one icon in its header too.** It still had the old bar over the text, while lessons already had the icon.

## [0.8.8] - 2026-11-04

### Added

- **Mermaid diagrams in notes.** A ```mermaid block in a note shows as its diagram. Click it to edit the source, and the diagram follows as you type.

### Fixed

- **Clearing a note's title no longer fills it from the body while you type.** The title stays empty until you leave the field; only then, if it is still empty, does the note take its first heading or line as its title.

## [0.8.7] - 2026-11-04

### Added

- **`/new` starts a mentor's conversation over.** Type it in the message box to clear the conversation, the same as Reset conversation in the mentor's settings; its soul and memory stay.

### Fixed

- **An Antigravity mentor recovers after Google refuses a reply.** When Antigravity answered with its own error, such as "User location is not supported", the next message failed with "Resource not found". The next message now restarts Antigravity and picks the conversation back up.

## [0.8.6] - 2026-11-04

### Changed

- **Mentors open faster on another computer.** A mentor's library and reader start loading as soon as you click it instead of after the other computer answers, and the learning map no longer reads the same courses twice.

### Fixed

- **This computer stays reachable from your other devices.** After a while the connection through the relay could drop and never come back, while your other computers still listed this one as there to connect to and then showed it offline. It now stays up, comes back on its own, and Settings → Remote access says when other devices cannot reach this computer and why.
- **A mentor with an empty conversation opens on another computer.** It stayed on "Opening the conversation…".

## [0.8.5] - 2026-11-03

### Fixed

- **Connecting to another computer no longer crashes Loci.** Pairing with a code, or opening the last computer at launch, quit Loci as soon as its window appeared, and from then on Loci quit at every launch. ([#43](https://github.com/Umupa/Loci/issues/43))

## [0.8.4] - 2026-11-03

### Fixed

- **No keychain password at every update.** With remote access set up, each new version asked twice at launch for the login keychain password. This device's key and its group's secret now live in files in Loci's data folder that only you can read; the first launch of this version asks one last time to move them out of the keychain.

## [0.8.3] - 2026-11-03

### Fixed

- **Clicking a notification opens the conversation.** A mentor's banner did nothing when its conversation had gone idle; it now brings the window forward on that mentor with its conversation showing.
- **Bold text in Chinese.** `**…**` next to Chinese punctuation such as “ or （ showed its asterisks and threw off the bold after it; it now bolds what was meant, and strikethrough does the same.

## [0.8.2] - 2026-11-03

### Fixed

- **Notifications read cleanly.** A mentor's banner is headed by its name instead of "Loci" and the first thing you said, and its reply shows as plain text rather than raw Markdown with links.

## [0.8.1] - 2026-11-03

### Changed

- **Translation is one icon in the reader's header.** The bar over a foreign source is gone. The translate icon by the lesson's actions is pale while nothing is translated, has a dot while some is still to do, and is ink once there is a translation; its menu reads in your language, the original or both, and asks your mentor for the rest. ⌥T flips between the translation and the original.

## [0.8.0] - 2026-11-03

A release about how Loci looks and reads: one quiet paper-and-ink look across the reader, the library and the conversation.

### Added

- **The learning map.** With nothing open, a mentor's reader shows its courses as a map: each lesson is a plot carrying its name, ink once read, grey while being read, pale stone until then, and the one to go on with is ringed in contour lines. A course the path names but nobody wrote yet is a dotted outline. Click a plot to open its lesson.
- **A book face for reading.** Lessons and documents are set in Literata, with LXGW WenKai for Chinese, both built in so they work offline. Settings → Appearance → Reading font switches to the interface sans or the system serif.
- **Loci Paper and Loci Ink themes**, a light and a dark paper with ink headings and no wallpaper.
- **A highlight is the note.** Selected text anywhere — a lesson, a document, a PDF, the conversation — has one bar: **Highlight** (H) and **Ask** (⌘L). A highlight's own bar takes a thought on it, asks about it, or deletes it. A table, diagram or code block in a reply has the same bar, and can be saved as a note of its own.
- **A course's highlights on one page**, from the link under its outline.
- **Start a course over** from its … menu or a right-click: every lesson goes back to unread, highlights and notes stay.
- **JetBrains Mono is built in** as a code font, so it is there on every machine.

### Changed

- **Mentor settings are a page of Settings** instead of a dialog that dimmed the window; each mentor has its own page, and resetting its soul and name is there. Default permissions for new mentors moved to Providers.
- **The course list is quieter.** No counts beside courses, chapters or path steps: the rule under a course fills with ink as you read. Chapters are plain headings whose fold arrow shows on hover, lesson titles keep to one line, and the status marks are ink, not blue.
- **The reader's head is a breadcrumb**, course / lesson, without a dropdown arrow; the course's name still opens its contents.
- **The composer** is one rounded field with a round send button that appears once there is something to send; +, the reading tag and the model share one row under it.
- **Settings rows** show a name and its control; what a setting does is on hover.
- **Code fonts** are offered under the names they are installed by on this computer, so fonts such as Cascadia (CaskaydiaCove on a Mac) can be chosen; fonts that are not installed are no longer offered, and Menlo, Monaco and PT Mono join the list.
- Citations in replies read as part of the sentence, scroll bars are thin and ink, and the top of a lesson is quieter.

### Fixed

- **Switching mentors takes one click.** A mentor switches on the press, and a click on an inactive window acts instead of only focusing it.
- **Selecting text stays in its column.** Dragging up out of the conversation no longer selects the reader and the library too.
- **Highlight and Ask on a lesson's source.** Selecting text in a lesson that reads a file showed no bar at all.
- A course of a few lessons draws a small map, not a few giant plots.

## [0.7.1] - 2026-11-03

### Fixed

- **Gemini works with a system SOCKS proxy.** With a proxy app such as Clash turning on the macOS SOCKS proxy, every Antigravity (Gemini) turn failed with "python-socks is required to use a SOCKS proxy". Loci now hands Antigravity the system HTTP(S) proxy and keeps its local connection off the proxy.

## [0.7.0] - 2026-11-03

### Added

- **Remote access.** Settings → Remote access lets your other devices use this computer's workspace. Mentors, courses, conversations, notes, PDFs and highlights stay here and are read and written here; the other device sends what you do and shows what comes back. It is off until you turn it on.
- **Pair with a code.** On the host, **Add device** shows a one-time code like `K7QM-2XPA` for 10 minutes; type it on the other Mac under **Connect to another computer** and its window opens. Nothing to set up: releases come with Loci's own relay and device registry. The code goes through a password-authenticated key exchange (SPAKE2), so the relay cannot learn the code or the group key, and a wrong guess spends the code.
- **Device groups.** Pairing puts both computers in one group. The device list shows every member, whether it is online and when it was last active; **Connect** opens a device and **Remove** revokes one for good. Under Advanced, the group's `loci-group:…` key can still be copied and pasted to join without a code.
- **Connect again in one click.** **File → Connect To** lists the computers that are online. Loci remembers the last one and, after the first pairing, opens it at launch when it is online; a window already open to that computer comes to the front instead of a second one.
- **A window connected to another device.** It looks like the host's own window: open a mentor, ask, answer approvals, take notes, highlight a PDF, and change the mentor's model and permissions from its settings dialog. A bar at the top names the host and says whether the connection is up.
- **Files on the host.** Choosing a file in a connected window browses the host's disk. Files and pictures dragged in or copied from this device are uploaded to the host first and keep their names.
- **Offline reading.** When the host cannot be reached, the window keeps showing what it read before and turns read-only: changes and new messages are refused rather than queued. Reconnecting catches up with the host.
- **The host stays awake.** While remote access is on and the host is plugged in, Loci prevents idle sleep. It still sleeps on battery or with the lid closed.
- **Your own services.** Under Advanced, name your own relay and registry instead of Loci's; a build without built-in services opens that section and asks for them. A device is named after the computer unless you name it.

### Changed

- In a window connected to another device, the model list and the settings that decide what the host does come from the host. Appearance, layout and shortcuts stay with this device.

### Fixed

- **The header row stays put.** Jumping to a section in a source could scroll the whole window up by the header's height, leaving the library toggle, back and forward, and the conversation's settings and close off screen until the app restarted. The shell no longer scrolls at all; only the reader inside it does.

## [0.6.1] - 2026-11-03

### Fixed

- **Gemini errors say what went wrong.** A failed turn through Antigravity used to show only `Internal error`. It now shows the ACP server's own explanation — a conversation it no longer has, an exhausted quota, a rejected request, or an expired sign-in — and offers the sign-in route only when credentials are the cause.

## [0.6.0] - 2026-11-02

### Added

- **Highlight a table, a diagram or a figure as a whole.** Hover a table, a Mermaid diagram, a code block or a picture in a source, guide, lesson or Markdown file and a small handle appears beside it; it opens the selection's bar: Highlight · Ask · Save to note · Copy. The mentor and your notes get the block as written (the table's Markdown, the diagram's source, the fenced code, `![alt](address)`), not its rendered words. A block's highlight follows it when the text around it changes. In a PDF, hold ⌥ (Option) and drag to draw an area around a figure or a table: highlight it, or ask about it or save it with the words inside the area and a picture of it (attached to the message, kept with the note).
- **The reader keeps your place.** Each mentor remembers where you were in each page: the page of a PDF, the paragraph of a source, guide, lesson or note, the line of a code file. Switching to another page or mentor and back, or restarting Loci, opens it there again. A link or `reader.open` that names a place still goes to that place. The last 50 pages per mentor are kept.
- **See what your mentor knows you are reading.** A small tag above a mentor's composer names the page open beside the chat and where you are in it: the course and lesson, the PDF page, a file's lines, and how many lines you have selected. It follows you as you scroll and select. Its × leaves the page out of the next message only; the one after carries it again.
- **`@` reaches your whole library.** The picker groups what it offers into courses, lessons, sources, guides, notes, highlights and files, each row saying where it lives (a lesson's course, a file's folder). With nothing typed it starts with what you opened lately and the lessons of the open course. Type `@资料/` or `@source/` (also `课程/` `course/`, `课/` `lesson/`, `导读/` `guide/`, `笔记/` `note/`, `高亮/` `highlight/`, `文件/` `file/`) to keep one group; Tab jumps from group to group. A mentioned course, lesson, source, guide or highlight reaches the mentor with how to read it.

### Changed

- **Lens answers a repository question in minutes.** Given a repository, Lens now reads it and writes a one-page brief — what it is and who it is for, the one data flow that explains it, 2–4 design decisions with links to the code, and the three files to read first — without saving the project's prose or building a course. Ask to go deeper ("深入读" or "带我读这个仓库") and it builds the 6–12 lesson course as before, with the brief as the last lesson of chapter 1.
- **Deleting a mentor deletes it.** Its folder (sources, guides, courses, notes, translations, repos, lab, Soul and memory) moves to the Trash, where you can still get it back: put it back where it was and Loci picks the mentor up again. Its conversation, highlights, lesson progress, reading places and view are deleted. Folders you gave it, a working folder outside its own and the shared `~/Loci/repos` are left alone. Before, the folder stayed on disk with `mentor.json` renamed. The same holds for `loci mentors delete`.
- **A calmer Courses list.** A learning path shows as its courses in order on one line, each with a numbered dot, its progress and a small "After 2, 3" tag while a course worth reading first is unread; the course you are in opens right under its row with its chapters and lessons, one course at a time, and clicking its row folds it. Without a path, courses are rows of the same kind (a single course shows its title and progress over its outline), with "Ask … for a course" and "Ask … to plan a path" at the end instead of a switcher menu. Lessons lose their numbers and show what they read (source, code tour or comparison) instead; titles take up to two lines, and an ordinal a mentor put in a course title ("一、", "1.") is left out. One style marks where you are, and the text comes in two sizes.

- **Save a passage to a note.** Selecting text, or clicking a highlight, offers **Save to note**: the passage goes to the end of a note as a Markdown quote, with a link back to its page, lines or section and your note on it under the quote. The first time you pick a note or start a new one; after that it goes to the note you used last, per mentor, with a chevron to choose another. A toast says where it went and opens the note. **Copy quote** puts the same Markdown on the clipboard.
- ⌘-click (Ctrl-click) a Loci link in a note, such as a saved passage, to open it in the app; a passage's link scrolls to its words and flashes them.

### Changed

- **Highlights and their notes, redone.** Selected text and an existing highlight get the same small bar beside the passage, in every reader (PDF, sources, guides, lessons, code): Highlight · Ask · Save to note · Copy, and on a highlight Note and Delete. The large highlight card is gone; a note on a highlight opens as a small field only when you ask for it, and shows as a line under the bar once written.
- **Ask puts the passage in the chat as a quote** and leaves the cursor after it for your question, instead of prefilling "Explain this passage.".
- Highlights are a pale wash of the mentor's colour, with no outline, the same on PDF pages and in text. Deleting a highlight asks first only when it has a note.

### Fixed

- Selecting text in a PDF no longer jumps when the pointer crosses the blank space between lines or columns, and a finished selection grows to the whole words it touches.

### Removed

- **Canvases.** The Excalidraw canvas is gone, with everything around it: the drawing pane and its library entries, Save to canvas, drawings in the `@` picker, `loci-canvas` cards and `loci://canvas` links, the built-in `loci_excalidraw` MCP server and its switch in Settings → MCP, the `canvas.*` app actions, `loci canvases …` and `loci reader open --canvas`, the `canvasTools` setting and a course's `canvasId`. On the first start, Loci deletes the canvas tables and each mentor's `canvases/` folder; nothing else in the folder is touched. Loci no longer looks for Node.js or Bun.

## [0.5.0] - 2026-11-01

### Added

- **A learning language.** Settings → General → Learning language (Follow my messages, 简体中文 or English) fixes what mentors write in: replies, course and lesson titles, guides, notes and reports, whatever language their sources are in. A term's original is given the first time it appears. Each mentor can choose its own in its settings. From a terminal: `loci settings set learningLanguage zh-CN` and `loci mentors update <mentor> --language en`.
- **Read a source in your language, beside the original.** Mentors translate the sections your lessons open (`documents.translate`; `loci sources translate` from a terminal), keeping the headings and leaving code untouched. The reader switches between the translation, the Original and Both, part by part; untranslated parts show in the original, out-of-date ones are marked, and **Ask … to translate** puts the request to your mentor. The original is never changed and stays what is cited, quoted and highlighted. PDF sources are not translated yet.
- **Edit notes as they read.** Notes open in an Edit view where Markdown takes shape as you type (headings, lists, tasks, quotes, code, tables, links and pictures); Source is one tab away. A note you only open is never rewritten.
- **Choose where "Add to notes" goes.** The first time, pick a new note or one you already have; after that the button names where it goes last, with a chevron to change it. Remembered per mentor.
- **Full-width text** in the ··· menu of lessons and documents lets the text run the width of its column.

### Changed

- A new app icon: Dew, a mentor's ink portrait, on pink. Loci Dev wears it on blue.
- One accent, taken from the open mentor's color: the selected lesson, the progress bar, reading marks, switches and focus rings follow whoever you are reading with. Links are ink with an underline in that color, and headings are ink.
- Reading status is one ink ring: empty, half filled while reading, solid with a tick once read.
- Icons are drawn at one, slightly heavier line weight, and corners come in three sizes.
- The lesson menu no longer offers "Mark as read" for readings (reaching the end marks them); it shows the highlight count as a badge and full-width text as a ticked setting.
- The mentor rail is narrower (60px on macOS); the window buttons sit a little closer together to fit.
- A mentor's **Other folders** lines up with the rows above it, with an Add folder button and each folder's path.
- The mentor settings button has its own icon, apart from the app's Settings.

## [0.4.0] - 2026-11-01

### Added

- **Each mentor is a folder.** A mentor lives in `~/Loci/<mentor>/`: `mentor.json`, `SOUL.md`, memory, `sources/`, `guides/`, `courses/`, `notes/`, `canvases/`, beside its `repos/`. You and the mentor can edit the files, and changes show up in Loci live. 0.3 data moves in automatically at the first start, after a backup in `<app data>/backups/`; nothing old is changed or deleted. Mentor settings show the folder with Reveal and **Export…** (a .zip), and the gallery has **Import a mentor…**. Deleting a mentor keeps its folder, so it can be brought back.
- **Pinned code tours.** A code lesson can name the commit it was written against (`repos/<owner>/<repo>@<sha>:path#L40-88`), and Loci shows the file as it was then. When the repository moves on and the file changes, a line under the title says so, with **Open current** and **Show pinned**, and the lesson's lines follow the edit when they can.
- **A code reader for Go, Rust, C, TypeScript, JavaScript and Python.** A **Symbols** outline in the header, ⌘-click to a definition, and **Definition** and **References** in the selection menu. Navigating from a pinned lesson stays at its commit. References match by name; there is no language server.
- **Back and forward in the reader.** ‹ › appear in the header once there is somewhere to go, and ⌘[ / ⌘] work too. Back returns to the lesson or the line you left, and undoes closing the reader.
- **Comparison lessons.** One lesson can put the same mechanism from 2–4 places on a page: lines of a file, a section of a source, or pages of a paper. Each part has a compact header, folds, can carry a one-sentence mentor's note, and works like a single lesson inside: highlighting, pin notices, highlights and notes, Ask, Definition and References. The mentor knows which part you are reading.
- **Learning paths.** A mentor can lay out 3–5 short courses in order, with optional prerequisites, in `courses/_path.yaml`. The Courses segment shows the path first: progress per course, planned courses (a click asks the mentor to write one), and "Best after …" while a prerequisite is unread, never a lock.
- **Papers as first-hand sources.** A PDF saved as a source is listed with its page count, opens in the PDF reader with highlights and notes, and is searchable. A link such as `loci://source/<id>#p7` opens the page and flashes the quoted passage, and a lesson can read a paper at its pages.
- **See what a mentor is doing.** A running turn lists its steps under the status line, newest first: saving a source, cloning a repository, fetching a page, writing a course. The conversation header names the newest step. What the turn saves carries a **New** mark in the library until you open it or the turn ends.
- **Full-text search** of a mentor's sources, guides, notes and papers, in any language.
- **New `loci` commands**: `storage status|migrate|reindex`, `library check|search`, `mentors export|import|relocate`, `code symbols|definition|references|read|pin|pins`, `path read|write`, and `reader open --at SHA` / `--page N`. `mentors turn` and `mentors send --wait --stream` report a turn's steps.

### Changed

- Mentors wear hand-drawn ink portraits (Notionists by Zoish, CC0) on a card tinted with their color, in place of the robot faces. Small avatars show the face alone and larger ones the head and shoulders. Mentors keep the face they had: each saved robot name, including its Neutral twin, maps to a portrait.
- The mentor rail is narrower. One highlight glides to the chosen mentor, faces lift and blink under the pointer, and a working mentor's tile carries a slow ring of light.
- The library's segments slide: one pill moves to the chosen segment while its label unfolds and the previous one folds away.
- A new app icon: an elephant in ink on paper, the animal said never to forget, after the memory Loci keeps for each mentor. Loci Dev is the same elephant in paper on ink, so the two are easy to tell apart in the Dock.
- A mentor keeps its provider, model, effort and permissions: they are saved with the mentor and start every new conversation, including after a reset, an import or a restart.
- A picture added to a mentor's note is stored beside the note in its folder; pictures older notes kept in the app data folder are copied there at the next start.
- An open note changed on disk shows **Changed on disk — Reload · Keep mine** when you have unsaved edits, and follows the disk quietly when you don't. An open drawing changed on disk reloads when nothing is unsaved.
- The Mentor and Lens templates plan paths for broad goals, pin every code lesson, write comparison lessons, and save papers as PDF sources.
- The app is about 8 MB larger, for the code reader's grammars.

### Fixed

- An unknown `loci` command or option is a usage error (exit 2) instead of starting the app.
- The first `loci mentors create` or `update` with `--provider` or `--model` after a cold start could stay on the previous provider.

## [0.3.0] - 2026-11-01

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

[Unreleased]: https://github.com/Umupa/Loci/compare/v0.8.9...HEAD
[0.8.9]: https://github.com/Umupa/Loci/compare/v0.8.8...v0.8.9
[0.8.8]: https://github.com/Umupa/Loci/compare/v0.8.7...v0.8.8
[0.8.7]: https://github.com/Umupa/Loci/compare/v0.8.6...v0.8.7
[0.8.6]: https://github.com/Umupa/Loci/compare/v0.8.5...v0.8.6
[0.8.5]: https://github.com/Umupa/Loci/compare/v0.8.4...v0.8.5
[0.8.4]: https://github.com/Umupa/Loci/compare/v0.8.3...v0.8.4
[0.8.3]: https://github.com/Umupa/Loci/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/Umupa/Loci/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/Umupa/Loci/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/Umupa/Loci/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/Umupa/Loci/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/Umupa/Loci/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/Umupa/Loci/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/Umupa/Loci/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Umupa/Loci/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Umupa/Loci/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Umupa/Loci/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Umupa/Loci/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/Umupa/Loci/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Umupa/Loci/releases/tag/v0.1.0
