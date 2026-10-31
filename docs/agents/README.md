# Agent Souls

Loci ships ready-made agents, one per kind of work. Click the **+** beside
*Agents* on the rail to pick one, or start from a blank agent. Adding one
writes its Soul once; edit it afterwards in the agent's **Settings → Soul**.

The Souls live in [`src/features/agents/templates`](../../src/features/agents/templates):

| File | Agent | What it produces |
| --- | --- | --- |
| [learning-guide.md](../../src/features/agents/templates/learning-guide.md) | Mentor | A course of primary sources, built after agreeing on a goal, with understanding tested as you read |
| [repo-lens.md](../../src/features/agents/templates/repo-lens.md) | Lens | A one-page brief and a code-tour course per repository, cloned under `~/Loci/repos` |
| [market-brief.md](../../src/features/agents/templates/market-brief.md) | Ledger | A market briefing saved as a note each trading day |

They rely on things the app provides: memory topics, which load into every
turn; courses whose lessons can show a range of lines from a source file; the
`<reading_now>` context naming what is open beside the chat; and habits, which
can run in Auto mode (`"access":"auto"`) so a risky step waits for you.
