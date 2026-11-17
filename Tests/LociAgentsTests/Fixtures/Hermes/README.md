# Hermes 协议用例

`synthetic-*.jsonl` 是根据 `main` 的 `src/integrations/harness/providers/hermes/` 中协议与 mock 测试构造的合同用例，**不是真实录音**。本机没有 Hermes，尚不能证明当前安装版本的协议兼容。

这些用例覆盖启动、模型/权限选择、流式回复、工具结果、审批选项、中断、`session/load` 和配置失败；会话 ID、模型、错误文案和 token 数量都是测试值。`resume` 还包含加载时重发的历史，验证它不会进入新回复。

拿到 CLI 后用 `LOCI_HERMES=/path/to/hermes LOCI_HERMES_RECORD=/tmp/hermes-recordings swift test --filter HermesLiveTests` 录制，再核对并脱敏。真实输出另存为 `hermes-*.jsonl`，不要覆盖或重命名构造用例来冒充录音。默认 `script/check` 不启动 Hermes。
