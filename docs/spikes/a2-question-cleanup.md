# α2：删除导师后的提问清理

在 `spike/ut-a2-question-cleanup` 的 `QuestionCleanupProbeTests` 用手动 agent 验证：同一笔记一个问题正在回答、另一个排队，删除导师并保留笔记后，会话已关闭，但两条待答项仍留在 `PendingAnswers`，均变成失败；预期删除导师后不再有其待答任务。

复现命令：`swift test --filter QuestionCleanupProbeTests`（先载入 `script/toolchain`）。测试在 `host.pendingAnswers(on: locator.content).isEmpty` 失败，关闭会话及未执行排队问题的检查通过。日志在该 worktree 的 `output/question-cleanup-probe.log`，不提交生成文件。

原因：`PassageQuestions.close` 只遍历已打开的会话，不移除 `asked` 或队列记录，也不等待队列结束。会话打开期间还不在 `sessions` 内；该时序需另行覆盖，不能只清空待答列表就认为整个生命周期已正确结束。

本轮保留问题，不调整任务生命周期。后续修复应同时覆盖：活动问题、排队问题、打开会话中的问题，以及删除后不能再保存回答或留下会话。一次性复现代码只留在 spike 分支。
