# Loci

Loci 是一个通用 agent 桌面外壳，使用 Tauri 2、Rust、React 19 和 Tailwind 4。项目仍然是本地文件夹，会话通过本机安装的 agent CLI 运行。

保留聊天、模型和权限选择、agent 提问、任务与计划显示、会话搜索、标签和拖拽分栏、设置、笔记及桌面通知。ACP 的通用协议核心也保留在 `src/integrations/harness/core`；当前内置 10 个 agent CLI 适配器。

当前开发和验收环境为 macOS arm64。需要 Node.js 20+、Rust/Cargo、rustfmt、Clippy 和 Xcode Command Line Tools；至少一家的 CLI 已安装并登录。

```sh
npm ci
npm run tauri dev
```

macOS 也可以用 `./script/build_and_run.sh --verify` 构建并启动 Release 应用，Codex 的 Run 按钮使用同一入口。该脚本会先停止本仓库已有的应用实例；`--help` 可查看调试与日志选项。

支持 Claude Code、Codex、Cursor、Grok Build、OpenCode、Pi、omp、fx、Hermes Agent 和 Antigravity。Agent CLIs 设置页可指定 CLI 路径、默认模型及是否显示在模型选择器；未安装的 CLI 仍显示在设置中。各 CLI 使用自己的登录配置，独立账号管理和额度查询目前仅支持 Claude Code/Codex。Antigravity 使用独立的 ACP server；遇到认证提示时点击应用内的 **Sign in to Antigravity** 完成 Google 登录，交互式 `agy` 的登录不能替代 ACP 认证。fx 暂不支持附件。

检查与构建：

```sh
npm run check
npm run build
```

`check` 包括 Vitest、TypeScript、Rust 格式、Clippy 和 Rust 测试。依赖版本沿用抽取时的锁文件。

在输入框以 `/operator` 开头，可在当前会话启用本地应用操作。agent 获得当前可执行文件的 `app` CLI 用法，能够读取模型、操作当前项目会话及分栏、整理会话文件夹、读写笔记。授权仅在启用该能力的会话的活跃 turn 中生效。

Excalidraw 画布是一等对象：每个 Claude Code / Codex 会话自动带上内置的 `loci_excalidraw` MCP。它运行未经修改的官方 Excalidraw MCP 服务，只把官方的 checkpoint 存储换成 Loci 画布，因此 agent 用官方的 `read_me` / `create_view` 直接在本地画布上创建和续画，人工修改会被保留，面板实时更新，结果写入 SQLite。该服务需要本机有 Node.js 20.11+（或 Bun）；没有时会话照常启动，Excalidraw 页面会说明原因。设计与验收见 [docs/canvas-mcp.md](docs/canvas-mcp.md)。

Loci 使用 `com.loci.desktop` 的独立应用数据目录，数据库为 `loci.db`。会话、笔记、布局、图片和隔离 provider 账号保存在该目录；应用不会迁入来源应用的数据。默认 provider 账号仍使用各 CLI 自己的登录和配置。

抽取范围与批准记录见 [docs/extraction.md](docs/extraction.md)，实际验收结果见 [docs/status.md](docs/status.md)。许可和来源声明见 [LICENSE](LICENSE)、[NOTICE](NOTICE)。
