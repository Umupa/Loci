# Loci

A Mac app for learning from what you read, watch and listen to, with one AI companion who lives in your library.

Loci keeps your articles, papers, videos and podcasts in one place and reads them with you. Its companion, also called Loci, runs on the agent CLI you already use, remembers what you have read together, and has a personality of its own.

Native Swift, macOS 26 and later. Still in alpha.

## What it does

**Loci, the companion.** One conversation that keeps going, and one beside every item in the library. Loci answers like a friend messaging you: short replies, an opinion when you ask which one is better. When you finish reading something or save something new, it shows up in the conversation.

**A soul and a memory, as plain files.** Everything that makes Loci who it is lives in the data folder under `agent/`, readable and editable:

| File | What it holds |
|---|---|
| `SOUL.md` | Who Loci is: a core you can edit, and traits it grows on its own (at most 15) |
| `USER.md` | What it knows about you |
| `MEMORY.md` | What is worth remembering for good |
| `notes/<date>.md` | What happened today, appended by every conversation |
| `diary/<date>.md` | What Loci wrote to itself at the end of the day |

Every night after 23:00, once you have gone quiet, Loci looks back on the day: it writes a diary entry, tidies its memory and may add a trait. The Loci page shows its soul, memory and diary, and lets you give it your own picture.

**Any agent CLI.** Loci runs on Claude Code, Codex, Pi, Grok, Cursor, OpenCode, Antigravity and others, using the login you already have. Switch the runtime at any time and it is still the same Loci; sessions underneath rotate on their own when the context fills up.

**A library.**

- Articles in a serif reader, papers as PDFs, and a built-in browser for pages that need a login.
- Videos and podcasts transcribed on your Mac with Whisper, with chapters, highlights and a line-by-line translation.
- Highlights anywhere: select a passage, keep a thought, or ask Loci about it right there.

**Your other Mac.** Pair two Macs through an end-to-end encrypted relay and switch to the other one's library and Loci from the sidebar. What you have opened stays readable offline.

## Build

Requires Xcode 27 or later.

```sh
script/check   # format, build, tests and architecture rules: the one gate
script/run     # build and open Loci (Beta)
```

`script/run --root <folder>` runs against a separate data folder instead of `~/Loci Dev`.

## Read more

- What is being built, and in what order: [docs/roadmap.md](docs/roadmap.md)
- Why it is built this way: [docs/design.md](docs/design.md)
- What each feature is called and how it should behave: [docs/features.md](docs/features.md)
- How the code is divided: [docs/architecture.md](docs/architecture.md)
- Rules for working here, for people and agents: [AGENTS.md](AGENTS.md)

Versions 0.2 to 0.11 were a Tauri app. Its code is kept at the `tauri` tag.

## License

[MIT](LICENSE)
