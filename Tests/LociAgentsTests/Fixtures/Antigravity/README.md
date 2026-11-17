# Antigravity 协议录音

真实录音于 2026-11-17 通过 `AntigravityLiveTests` 对本机官方 `agy_acp_server.par` 录制，`initialize` 返回 `antigravity-acp` 1.3.0。不是交互式 `agy`（本机版本 1.5.3）。

- macOS 启动参数为空，进程工作目录为 `.par` 所在目录；`session/new.cwd` 是独立临时目录，未使用 `~/Loci`。
- 按 Pi 的录音格式保存 `launch`、`to`、`from`、`close`、`exit`，保留实际 JSON-RPC 消息顺序。
- 本机目录替换为 `$FOLDER`/`$HOME`，当前模型替换为 `some-model`。保留配置选项、工具请求与输出；含账户信息的标准错误日志全部移除。
- 输入关闭后三秒仍未退出时发送 SIGTERM；保留 Foundation 报告的实际退出状态。
- `reply`、`tool`、`interrupt`、`resume`、`resume-missing`、`bad-model` 均为真实录音，覆盖回复、工具、停止后续聊、恢复及错误。
- `capacity-error` 来自复跑权限允许场景：服务端把容量不足作为普通文本返回，随后仍发送 `end_turn`。回放要求该回合失败。导师改为一律完全权限后，录音里 `session/set_mode` 的 `default` 改成了 `yolo`，其余未动。
- 文件读取的完成通知可能没有正文；命令输出在 `rawOutput.combinedOutput`，拒绝的说明在字符串 `rawOutput`。
- `synthetic-*` 基于真实握手构造失败或配置分支，不是实际服务端输出：权限模式设置失败、指定模型、回复达到 token 限制。

`AntigravityReplayTests` 在 `script/check` 中回放这些录音，无需安装或登录服务端。真实测试默认跳过，设置 `LOCI_ANTIGRAVITY=<.par 路径>` 开启；增加 `LOCI_ANTIGRAVITY_RECORD=<目录>` 可重录。
