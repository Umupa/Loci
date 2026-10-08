# Documentation

Start with the [project README](../README.md) for what Loci is and how to run it. The rest of the documentation is here.

| Document | Language | What it covers |
| --- | --- | --- |
| [architecture.md](architecture.md) | English | How the app is put together: processes, agent CLI adapters, storage, the control channel, the built-in MCP servers, trust boundaries |
| [canvas-mcp.md](canvas-mcp.md) | 中文 | Excalidraw canvases and the built-in `loci_excalidraw` MCP server: design, semantics, limits and verification records |
| [learn.md](learn.md) | 中文 | `/learn`: product decisions, requirements, data model, architecture, and a record of what was and was not verified |

Files at the root of the repository:

| File | Purpose |
| --- | --- |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Setting up, checks to run, how to propose a change |
| [SECURITY.md](../SECURITY.md) | Reporting a vulnerability, and what counts as one |
| [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) | Community standards |
| [CHANGELOG.md](../CHANGELOG.md) | What changed in each release |
| [NOTICE](../NOTICE) | Origin of the code, bundled third-party software, trademarks |

The earlier extraction plan and acceptance notes are no longer kept in the tree. They remain in git history: `git log --follow -- docs/extraction.md`.
