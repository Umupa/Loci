# The Loci command line

`loci` drives a running Loci from any terminal: mentors, their courses, sources, notes, canvases and files, the reader, and the settings tests need. End-to-end tests and the [mentor evaluation](evaluation.md) use it, and so can an agent outside Loci (Claude Code, Codex, Antigravity, ...) acting as a mentor.

It is the same executable as the app. `loci <command> <verb>` runs a command and exits; it never starts the app.

```sh
loci --help                     # the commands
loci mentors --help             # the verbs of one command
loci mentors create --help      # the options of one verb
```

## Getting `loci` on your PATH

Settings → General → Command line → **Install** links `~/.local/bin/loci` to the build you clicked it in. Make sure `~/.local/bin` is on your `PATH`. On Windows, call the executable by its full path or add its folder to `PATH`.

## Which Loci it talks to

Every build has its own identifier, data folder and token: the installed app is `com.loci.desktop`, Loci Dev is `com.loci.desktop.dev`, and a QA bundle has whatever identifier it was built with. `loci` talks to:

1. the identifier given with `--app`, else
2. `LOCI_APP_ID`, else
3. the identifier the executable itself was built with, read from its bundled configuration.

So the `loci` inside `Loci Dev.app` talks to Loci Dev, and the one inside a QA bundle talks to that QA build. A QA build is a release bundle with its own identifier:

```sh
npx tauri build --config src-tauri/tauri.dev.conf.json --config '{"identifier":"com.loci.desktop.qa"}'
"target/release/bundle/macos/Loci Dev.app/Contents/MacOS/loci" status          # this QA build
loci --app com.loci.desktop.qa status                                            # the same, from any loci
```

`loci status` reports whether that Loci is running, with its identifier and version.

## Access

- A running Loci writes `<app data>/control/endpoint.json` (where it listens on loopback) and `<app data>/control/cli-token`. Both are readable only by your user account (`0600`, in a `0700` folder); `loci` refuses a token file other users could read.
- Every request carries the token. It is compared in constant time. It opens only the command line's own namespace: it cannot act as an agent's turn grant, and an agent's turn grant cannot act as it.
- Access is **on by default** in every build. Settings → General → Command line turns it off (that removes the token, so copies stop working too) and rotates the token. `loci cli rotate-token` and `loci cli disable` do the same from a terminal; turning it back on is only possible in Settings.
- Agents inside Loci keep their own per-turn access (`loci app`); this switch does not change it.

Anything running as your user can read the token, just as it can read Loci's database. That includes an agent in Full access mode. See [SECURITY.md](../SECURITY.md).

## Output and exit status

Every command prints one JSON object: `{"ok":true,"result":...}` or `{"ok":false,"error":"...","code":"..."}`. On a terminal it is indented, and piped it is one line. `--json` is accepted and changes nothing.

| Exit | `code` | Meaning |
| --- | --- | --- |
| 0 | — | Done |
| 1 | `failed`, `not_found`, `busy` | Loci refused or could not do it |
| 2 | `usage` | Wrong command, option or value; nothing was sent |
| 3 | `not_running` | That Loci is not running (or no window came up) |
| 4 | `unauthorized`, `disabled` | No usable token, or access is off |
| 5 | `timeout` | No answer in time; the command may have run (retry with the same `--request-id`) |
| 6 | `declined`, `needs_you` | You declined a confirmation, or the mentor is waiting for you |

`--request-id ID` names a call: a retry with the same ID and input gets the first answer and is not run twice.

## Arguments

- Positional arguments fill a verb's positional fields in order (`loci mentors send <mentor> <text>`).
- Every field is also an option: `--source-url https://...`, `--max-chars 400`, `--yes` / `--no-yes`.
- `--<field>-file PATH` reads a field from a file, or from stdin with `-`: `--text-file prompt.md`, `--body-file -`.
- `--input FILE` (or `-`) takes the fields from one JSON object; options given beside it win. This suits `courses write --input course.json`.
- A mentor is named by id or by its name, when that is unique.

## Commands

| Command | Verbs |
| --- | --- |
| `status` | Whether this Loci runs, and its identifier and version |
| `templates` | `list` |
| `mentors` | `list`, `show`, `create`, `update`, `delete`, `reset`, `switch`, `send`, `turn`, `read`, `stop`, `export`, `import`, `relocate` |
| `sources` | `list`, `read`, `write` (take a Markdown file someone published in as a first-hand source) |
| `guides` | `write`: save the mentor's own guide (a reading guide, a brief), from `--path` or `--body`/`--body-file`; listed and labelled apart from sources |
| `courses` | `list`, `read`, `write`, `delete`, `lesson` (mark read, reading or untouched) |
| `notes` | `list`, `read`, `write`, `delete` |
| `canvases` | `list`, `get`, `create`, `rename`, `delete`, `read-data`, `write-data` |
| `files` | `list`, `read`, `write`, in the mentor's working folder and the folders it was given |
| `reader` | `open`, `show`, `close` (`open --source ID --quote TEXT` shows and flashes a passage) |
| `annotations` | `list`, `counts`, `add`, `note`, `delete`: the learner's highlights and notes on sources, files and lessons |
| `library` | `open`, `show`: the mentor's left column (segment, course, filter); `check`: files in the mentor's folder Loci could not read; `search`: full-text search of its sources, guides and notes |
| `storage` | `status`, `migrate` (`--dry-run`, `--redo <mentor id>`), `reindex`: mentors' folders and the move of 0.3 data into them |
| `sessions` | `list`, `read`, `start`, `send`, `draft`, `stop`, `archive`, `delete` |
| `soul`, `memory`, `habits` | The mentor's standing instructions, memory and habits |
| `models` | `list`: providers and their current models (each catalog is read first, waiting up to five seconds), settings and permission modes |
| `settings` | `get`, `set`: `defaultProvider`, `defaultModel`, `defaultMentorAccess`, `canvasTools` |
| `updates` | `check`: whether GitHub Releases offers a newer installed Loci, without opening the update prompt |
| `cli` | `rotate-token`, `disable` |

Notes:

- `mentors create` and `update` take `--provider` (any agent CLI id; `agy` means `antigravity`), `--model`, `--effort`, `--mode` (`supervised`, `auto-accept-edits`, `auto`, `full-access`), `--name`, `--role`, `--workdir`, `--avatar`, `--color`. Creating a mentor does not switch the window to it (`--switch` does) and does not run a model. With `--provider` or `--model`, the provider's catalog is read first, so a model only the CLI knows (grok's custom models, say) is visible in a fresh window; `sessions start` does the same.
- `mentors send` returns `{mentor, sessionId, turn}` as soon as the message is accepted. `--wait` follows the turn until it is done (`--timeout`, default 900 s). `--stream` also prints what the mentor is doing as it happens: one JSON line per new activity entry (`{"type":"activity","id":…,"kind":…,"text":…,"status":…}`), then the reply as it grows (`{"type":"delta","text":…}` or `{"type":"replace","text":…}`), then `{"type":"done","response":...}`. `mentors turn <mentor> <turn>` reads a turn's state later: `queued`, `running`, `needs-you`, `done` or `failed`, with the reply so far, `tools`, the number of tool calls it made, and `activity`, its human progress lines newest first (the same entries the mentor's transcript shows, each with `type: "activity"`, a stable `id`, `kind`, `status` and, for a save, `saved`). A busy mentor refuses a new message (`busy`).
- `reader open --mentor M` takes exactly one of `--course C [--lesson L]`, `--source S [--section "Heading"]`, `--note N`, `--canvas K`, `--file /abs/path [--lines 10-40 | --page 3]`. It replaces what that mentor's reader shows. When the mentor is not on screen, the page is ready for when it is; `--switch` brings it on screen. `reader show` reports the kind, id or path, lesson and requested place.
- `library open --mentor M` takes any of `--segment courses|sources|notes|files`, `--course C` (the course the Courses segment shows; it does not open the reader, `reader open --course C` does) and `--filter TEXT` (the filter of the segment shown; empty clears it; Courses has none). It also shows the library if it was hidden, and `--switch` brings the mentor on screen. `library show` reports `visible`, `segment`, `course` and `filter`. A mentor without a chosen segment shows Courses when it has a course, else Sources. The segment and course are remembered per mentor; the filter lasts until the window closes.
- `mentors delete` and `mentors reset` ask in Loci, as the rail does. `--yes` skips the question on Loci Dev and QA builds only; the installed app always asks, and `loci` waits for the answer (exit 6 when declined).
- `updates check` returns `{available, version, current}`: `version` is the newer release (null when there is none) and `current` is the running version. It only reads GitHub Releases; it never opens the update prompt. A build from source reports `available: false` without asking.
- Library commands run exactly as the mentor's own `loci app` actions do (`sources write` is `documents.write`, `guides write` is `guides.write`, `canvases` is `canvas.*`), with the same rules. `sources list` gives each entry's `kind`: `source` (with `sourceUrl`) or `guide`. A guide cannot take a source's id, nor a source a guide's. Sessions started from a terminal do not report back to the mentor unless `--notify-on-complete`.

- `mentors export <mentor> --out /abs/file.zip [--with-repos]` zips the mentor's folder (library, courses, notes, drawings, Soul, memory, progress, highlights; `repos/` and `lab/` only with `--with-repos`). `mentors import --path file.zip` makes a new mentor from it, with a new id when this Loci already has the same one; `mentors import --folder /abs/folder` brings back a mentor folder where it is (after a reset, or `mentors delete`, which keeps the folder). `mentors relocate <mentor> [--workdir /abs/folder]` points the working folder elsewhere, or back at the mentor folder; nothing is moved.
- `storage status` reports the mentors root and each mentor's folder and file counts; `storage migrate --dry-run` lists what the move of 0.3 data would write, without writing. `library check` and `library search` work on a mentor's folder; a mentor's own `loci app` has them too, for its own folder.

Mentors inside Loci can also use `reader.open`, `reader.show` and `reader.close`, and `library.open` and `library.show`, through `loci app`, for their own reader and library.

If no Loci window is listening, the command shows or opens the main window and waits for it.

## Tests

`scripts/e2e/smoke.sh` runs the whole path against a running Loci Dev or QA build: create a mentor on Antigravity with Full access, take in a source, save a course, open a lesson and a section, highlight and note a passage and count it on its lesson, open a quoted passage, ask the mentor a question and wait for the reply, mark the lesson read, and delete the mentor.

```sh
LOCI_APP_ID=com.loci.desktop.qa \
LOCI_BIN="target/release/bundle/macos/Loci Dev.app/Contents/MacOS/loci" \
scripts/e2e/smoke.sh
```

`LOCI_SMOKE_PROVIDER` changes the provider, and `LOCI_SMOKE_SEND=0` skips the question (no model runs). The script refuses `com.loci.desktop` unless `LOCI_ALLOW_RELEASE=1`.

From JavaScript, `scripts/e2e/loci.mjs` wraps the same calls:

```js
import { lociCli } from "./scripts/e2e/loci.mjs";
const loci = lociCli({ app: "com.loci.desktop.qa", bin: process.env.LOCI_BIN });
const mentor = await loci.call("mentors", "create", "--template", "learning-guide", "--provider", "agy");
const reply = await loci.call("mentors", "send", mentor.id, "What should I read first?", "--wait");
```

`call` returns the result or throws a `LociCliError` with `code` and `exitCode`. Like the script, it refuses the installed app unless told otherwise.

## Acting as a mentor from outside Loci

An agent outside Loci can do a mentor's work: gather material with its own tools, then put it where the user reads. Something like this in its `CLAUDE.md` or `AGENTS.md` is enough:

```md
You prepare reading for the user in Loci, through the `loci` command line (run `loci --help`).
- Work for one mentor: `loci mentors list`, or `loci mentors create --template learning-guide --name "<topic>"`.
- Save what you fetched as a Markdown file, then take it in:
  `loci sources write --mentor <id> --id <slug> --title "<title>" --path /abs/file.md --source-url <where it was published>`.
- Arrange sources into a course: `loci courses write --mentor <id> --input course.json`
  (the format is in `loci app --help`, "Reading course").
- Show the user where to read: `loci reader open --mentor <id> --course <course> --lesson <lesson>`,
  or `--source <slug> --section "<heading>"`, or a passage: `--source <slug> --quote "<verbatim words>"`.
- See what the user marked: `loci annotations list --mentor <id> --course <course>` (highlights and their notes).
- Keep open questions in a note: `loci notes write --mentor <id> --title "Open questions" --body-file notes.md`.
Every command prints JSON; a non-zero exit status means it did not happen.
```

## Adding a command

Commands live in `src/app/commands`. Add one `CommandDefinition` (name, summary, fields, callers, and the function it runs, which is the function the UI calls) to one of the lists in `src/app/commands/index.ts`, then run `npm run gen:cli`. That writes `src-tauri/resources/cli-commands.json`, which `loci` reads for parsing and help. A test fails while the manifest is stale. `callers: ["agent"]` also offers the command to mentors' own `loci app`.
