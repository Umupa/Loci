# Agent Souls

Standing instructions for the agents Loci is used with. Loci ships no agent
templates: create a blank agent with the **+** beside *Agents* on the rail,
open **Settings → Soul**, and paste one of these in. Edit freely afterwards;
the copy here is only a starting point.

| File | Agent | What it produces |
| --- | --- | --- |
| [repo-lens.md](repo-lens.md) | Reads an open-source repository quickly | A one-page brief and a code-tour course per repository, cloned under `~/Loci/repos` |
| [market-brief.md](market-brief.md) | Writes a scheduled market briefing | A note tagged `briefing` each trading day, read in **Feeds → Briefings** |

Both rely on things the app provides: memory topics, which load into every
turn; courses whose lessons can show a range of lines from a source file; the
`<reading_now>` context naming what is open beside the chat; and habits, which
can run in Auto mode (`"access":"auto"`) so a risky step waits for you.
