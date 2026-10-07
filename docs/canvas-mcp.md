# UMP-7 · Excalidraw 绘图接入

## 决策

保留官方 Excalidraw MCP 为独立的图形设计/预览工具，通过已有 `/operator` CLI 读写 Loci 的本地画布。无需内置第二套 MCP 服务，也不把远端 checkpoint 当成本地画布 ID。

依据：[官方 MCP 项目](https://github.com/excalidraw/excalidraw-mcp)以 MCP Apps 交互图为输出；当前实际安装地址是 `https://mcp.excalidraw.com/mcp`。本次实际调用 `read_me` 和 `create_view`，两个标签矩形和箭头生成成功，返回 checkpoint `acb0007536f4478aab`。当前可调用工具没有接受 Loci canvas ID 的本地持久化接口。

MCP 的绘图格式包含 `cameraUpdate`、`delete`、`restoreCheckpoint` 等流式指令。它们不是 Excalidraw 元素，不能直接写入 Loci；应将最终图形整理为实际场景。外部 MCP 不可用时，Agent 仍可直接用本地 CLI 绘图。

## 本地接口

先在 Session 启用 `/operator`，按提示获得 CLI 的真实路径，执行 `app --help`。

- `canvas.list` / `canvas.get` 保持元数据读取。
- `canvas.create` 创建当前项目的空画布，返回本地 ID。
- `canvas.read-data {"id":"..."}` 返回 `id`、`title` 和 `dataJson`，读取前等待打开面板的待保存编辑。
- `canvas.write-data {"id":"...","dataJson":"..."}` 校验、转换并替换当前项目的画布场景，返回 `{"updated":true}`。已打开面板立即更新，替换可通过 Excalidraw Undo 撤销。

`dataJson` 是 JSON **字符串**，其中的对象包含 `elements` 数组及可选的 `appState`、`files` 对象。基础图形支持 Excalidraw programmatic 格式，补齐可编辑元素及标签；已有完整原生场景保留元素 ID、绑定和图片。含图片、框架、自由笔画的场景应使用完整原生元素。一次写入必须全部为原生元素或全部为简写元素；混合输入会被拒绝，扩展原生场景前须先规范化新增元素。图片资源 ID 按内容规范化，防止编辑器缓存旧图片。持久化的 appState 仅包含背景和当前字体，视口及选择状态留在界面。

例如先创建画布，再用返回 ID 写入以下场景（外层请求须把该对象序列化到 `dataJson`）：

```json
{
  "elements": [
    {"type":"rectangle","id":"agent","x":80,"y":160,"width":200,"height":80,"label":{"text":"Agent"}},
    {"type":"rectangle","id":"canvas","x":440,"y":160,"width":220,"height":80,"label":{"text":"Loci Canvas"}},
    {"type":"arrow","id":"flow","x":280,"y":200,"width":160,"height":0,"points":[[0,0],[160,0]],"start":{"id":"agent"},"end":{"id":"canvas"}}
  ],
  "appState": {"viewBackgroundColor":"#ffffff"},
  "files": {}
}
```

写入是全量替换。扩展已有画布前先读取，保留原元素和 files；不自动合并并发编辑。跨项目 ID、非法结构、伪元素、重复 ID 和存储失败返回错误，不报告成功。输入上限为 250000 UTF-8 字节，CLI 整个 JSON 请求还有 262144 字节限制（包括转义），大型图片场景可能无法通过此入口传输。

## 验证

- 真实 MCP 工具生成成功。
- 自动测试使用实际安装的 Excalidraw 0.18.1 转换 API，验证标签生成、箭头绑定、原生 ID 与图片保留、非法输入、队列顺序、项目隔离和失败路径；happy-dom 仅替代字体测量环境。
- 浏览器实际挂载 `CanvasPane`，通过 `handleAgentApp` 写入上述图形，确认已有画布直接显示图形与标签；读回 5 个元素；Undo 后读回 0 个可见元素，Redo 后恢复 5 个。截图：`/tmp/loci-ump7-browser.png`。
- 浏览器验证的持久化边界采用内存 invoke 适配器；未把它宣称为真实 provider 会话、Tauri SQLite 或重启验收。临时验证页面在验证后删除。
- 最终 `npm run check` 通过：221 个前端测试文件、2497 项测试、TypeScript、Rust fmt、Clippy `-D warnings`、171 项 Rust 测试。`npm run build` 和 `git diff --check` 通过。日志分别保留在 `/tmp/loci-ump7-check.log`、`/tmp/loci-ump7-build.log`。
