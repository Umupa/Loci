# Documentation

Start with the [project README](../README.md) for what Loci is and how to run it. The rest of the documentation is here.

| Document | Language | What it covers |
| --- | --- | --- |
| [roadmap.md](roadmap.md) | 简体中文 | 产品定位与分阶段路线图：M0 减法、M1 新布局、M2 陪你读、M3 读码、M4 实验、M5 沉淀 |
| [architecture.md](architecture.md) | English | How the app is put together: processes, agent CLI adapters, storage, the control channel, the built-in MCP servers, trust boundaries |
| [cli.md](cli.md) | English | The `loci` command line: reaching Loci Dev or a QA build, access and the token, commands, exit codes, end-to-end tests, acting as a mentor from outside Loci |
| [evaluation.md](evaluation.md) | English | Measuring mentor quality: `npm run eval`, scenarios, the scripted learner, automatic checks, the agy-judged rubric, the baseline |
| [remote-access.md](remote-access.md) | 简体中文 | 远程访问设计稿：笔记本做主机，其他设备经隧道接入；Transport、命令白名单、会话主控、Tunnel、设备组、客户端缓存 |
| [remote-session.md](remote-session.md) | 简体中文 | 远程访问的会话主控：一轮对话的状态流、广播接缝、意图表、P1 任务拆分 |
| [remote-settings.md](remote-settings.md) | 简体中文 | 远程访问的设置：localStorage 逐键分类（主机共享 / 每台设备各自），settings 通道与客户端镜像方案 |
| [remote-deploy.md](remote-deploy.md) | 简体中文 | 远程访问部署指南：在 Cloudflare 上部署 alma-relay 和设备注册表，配置主机和客户端，安全与排查 |
| [learning.md](learning.md) | 简体中文 | 和导师一起阅读：选中即问、高亮与笔记、阅读位置、跳转到原文、本地存储 |
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
| [releasing.md](releasing.md) | Loci and Loci Dev, the release workflow, updates and signing |
| [NOTICE](../NOTICE) | Origin of the code, bundled third-party software, trademarks |

The earlier extraction plan and acceptance notes are no longer kept in the tree. They remain in git history: `git log --follow -- docs/extraction.md`.
