# Antigravity 协议录音

真实录音于 2026-11-27 通过 `AntigravityLiveTests` 对本机 `agy acp`（Antigravity CLI 1.5.18）录制，启动参数是 `acp --dangerously-skip-permissions`，进程工作目录与 `session/new.cwd` 都是独立临时目录。

- 按 Pi 的录音格式保存 `launch`、`to`、`from`、`close`、`exit`，保留实际 JSON-RPC 消息顺序。
- 本机目录替换为 `$FOLDER`/`$HOME`，当前模型替换为 `some-model`。`session/list` 换成一条虚构会话，斜杠命令只留 `compact`、`plan`、`goal`，订阅档位换成 `Some Tier`；标准错误全部移除。
- 输入关闭后三秒仍未退出时发送 SIGTERM；保留 Foundation 报告的实际退出状态。
- `reply`、`tool`、`interrupt`、`resume`、`resume-missing`、`bad-model` 均为真实录音，覆盖回复、工具、停止后续聊、恢复及错误。
- `capacity-error` 是 2026-11-17 对旧 `agy_acp_server.par` 的真实录音：服务端把容量不足作为普通文本返回，随后仍发送 `end_turn`。回放要求该回合失败。换到 `agy acp` 后去掉了其中的 `session/set_mode` 并重排请求编号，其余未动。
- 文件读取的完成通知可能没有正文；命令输出在 `rawOutput.combinedOutput`，拒绝的说明在字符串 `rawOutput`。
- `synthetic-*` 基于旧服务的真实握手构造配置或失败分支，不是实际服务端输出：模型选择器、指定模型、回复达到 token 限制。

`AntigravityReplayTests` 在 `script/check` 中回放这些录音，无需安装或登录服务端。真实测试默认跳过，设置 `LOCI_ANTIGRAVITY=<agy 路径>` 开启；增加 `LOCI_ANTIGRAVITY_RECORD=<目录>` 可重录。
