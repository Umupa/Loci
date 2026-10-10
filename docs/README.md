# Documentation

Start with the [project README](../README.md) for what Loci is and how to run it. The rest of the documentation is here.

| Document | Language | What it covers |
| --- | --- | --- |
| [architecture.md](architecture.md) | English | How the app is put together: processes, agent CLI adapters, storage, the control channel, the built-in MCP servers, trust boundaries |
| [learning.md](learning.md) | 简体中文 | 交互讲解、来源提问、PDF 高亮批注、作品保留、真实验收效果与截图，以及生成接口 |
| [canvas-mcp.md](canvas-mcp.md) | 中文 | Excalidraw canvases and the built-in `loci_excalidraw` MCP server: design, semantics, limits and verification records |
| [stability-validation.md](stability-validation.md) | 中文 | Session persistence, background work and rendering: regression checks, measurements and remaining verification limits |
| [localization.md](localization.md) | 中文 | Settings language preferences, translation boundaries and UI verification |
| [themes.md](themes.md) | 中文 | Omarchy themes, wallpapers and fonts: settings, palette mapping, importing assets and verification |

Files at the root of the repository:

| File | Purpose |
| --- | --- |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Setting up, checks to run, how to propose a change |
| [SECURITY.md](../SECURITY.md) | Reporting a vulnerability, and what counts as one |
| [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) | Community standards |
| [CHANGELOG.md](../CHANGELOG.md) | What changed in each release |
| [NOTICE](../NOTICE) | Origin of the code, bundled third-party software, trademarks |

The earlier extraction plan and acceptance notes are no longer kept in the tree. They remain in git history: `git log --follow -- docs/extraction.md`.
