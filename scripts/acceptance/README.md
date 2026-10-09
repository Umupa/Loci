# Live acceptance probes

Small scripts that exercise Loci's real protocol code against real agent CLIs. They are run by hand. They are not part of `npm test` or CI, because they need signed-in CLIs and send real prompts.

Node replaces only the native process transport. The protocol and provider code is bundled from `src/` with esbuild, and every server response comes from the real CLI, so a pass is evidence the production code works against that CLI version, which the mocked `*Live.test.ts` files cannot give.

| Script | What it does |
| --- | --- |
| `real-protocol.mjs acp [workspace]` | Starts `codex-acp` (it must be on your `PATH`) and drives the production ACP client through initialize, session creation, model selection, a streamed reply, an error response and cancellation |
| `real-protocol.mjs codex-plan [workspace] [model]` | Runs a Codex turn in plan mode through the production provider and checks that question, task and plan events arrive. The default model is `codex:gpt-6.1-sol` |
| `mcp-fixture.mjs <marker> <log>` | A disposable stdio MCP server with one tool, for checking that an agent can call an MCP server you configured. The marker must start with `LOCI-MCP-` |
| `learn/skillTurn.probe.ts` | One turn of a real `/learn` conversation with Claude Code or Codex: the production prompt, the real `loci_learn` MCP server and the production bridge, with only the window and SQLite replaced. For judging the learning skill's prompt by what an agent does with it |

```sh
node scripts/acceptance/real-protocol.mjs acp /path/to/a/scratch/folder
```

Use a scratch folder you do not mind the agent reading. Without a `workspace` argument the script makes a temporary one. Each run writes a JSON report into that folder (`<mode>-acceptance.json`) and exits non-zero if a check fails. A missing event counts as a failure; it is not skipped.

## The learning skill

Most of `/learn` is a prompt (`src/features/learn/learnCommand.ts`), so a change to it can only be judged by running it. The probe runs one turn and stops, so that you can read what the agent said and write the learner's next message yourself:

```sh
LEARN_PROBE_DIR=/scratch/k8s LEARN_PROBE_HARNESS=codex \
LEARN_PROBE_MESSAGE='/learn kubernetes' \
npx vitest run --config scripts/acceptance/learn/vitest.config.ts
```

Run it again with the same `LEARN_PROBE_DIR` and the next `LEARN_PROBE_MESSAGE` to continue the conversation; the first message starts with `/learn`. `LEARN_PROBE_HARNESS` is `claude` or `codex` and is fixed by the first turn, `LEARN_PROBE_MODEL` picks a model, `LEARN_PROBE_MESSAGE_FILE` reads a long message from a file, and `LEARN_PROBE_LANGUAGES` (for example `zh-CN,en`) stands in for the system languages the app reports to the agent.

The folder gets `project/` (the subject's folder, where the agent writes `profile.md`, `roadmap.md` and `sources/`), `transcript.md` (what the agent said and every tool it used, with the app's answer to each learning call), `map.md` (the learning map as text), `events/` (the CLI's raw output) and `state.json`. The agent runs with its permission checks off, as in Loci's Full access mode, so use a scratch folder with nothing beside it that you would not want it to read. A setup that gathers readings for a whole roadmap takes tens of minutes and a matching share of your usage; ask for one or two stages when you only want to see how it goes.

The probe has no window. It does not show how the map looks, and Claude Code's question cards are turned off, so questions arrive as text. Check those in the app.

The separate `stability/` fixtures run offline with `npm run test:stability`; they do not need signed-in agent CLIs. See [the stability validation record](../../docs/stability-validation.md) for the persistence tests, browser fixtures and measurements.
