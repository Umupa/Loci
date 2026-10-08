# Live acceptance probes

Small scripts that exercise Loci's real protocol code against real agent CLIs. They are run by hand. They are not part of `npm test` or CI, because they need signed-in CLIs and send real prompts.

Node replaces only the native process transport. The protocol and provider code is bundled from `src/` with esbuild, and every server response comes from the real CLI, so a pass is evidence the production code works against that CLI version, which the mocked `*Live.test.ts` files cannot give.

| Script | What it does |
| --- | --- |
| `real-protocol.mjs acp [workspace]` | Starts `codex-acp` (it must be on your `PATH`) and drives the production ACP client through initialize, session creation, model selection, a streamed reply, an error response and cancellation |
| `real-protocol.mjs codex-plan [workspace] [model]` | Runs a Codex turn in plan mode through the production provider and checks that question, task and plan events arrive. The default model is `codex:gpt-6.1-sol` |
| `mcp-fixture.mjs <marker> <log>` | A disposable stdio MCP server with one tool, for checking that an agent can call an MCP server you configured. The marker must start with `LOCI-MCP-` |

```sh
node scripts/acceptance/real-protocol.mjs acp /path/to/a/scratch/folder
```

Use a scratch folder you do not mind the agent reading. Without a `workspace` argument the script makes a temporary one. Each run writes a JSON report into that folder (`<mode>-acceptance.json`) and exits non-zero if a check fails. A missing event counts as a failure; it is not skipped.

The separate `stability/` fixtures run offline with `npm run test:stability`; they do not need signed-in agent CLIs. See [the stability validation record](../../docs/stability-validation.md) for the persistence tests, browser fixtures and measurements.
