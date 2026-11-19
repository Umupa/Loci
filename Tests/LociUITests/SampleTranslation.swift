import LociModel

extension Sample {
  /// The Borg article's passages in Chinese, keyed by their Markdown as the host sends them.
  static func borgInChinese() throws -> ArticleTranslation {
    try ArticleTranslation(
      language: "zh-Hans",
      passages: [
        .init(source: "# Large-scale cluster management at Google with Borg", text: "# 用 Borg 在 Google 做大规模集群管理"),
        .init(source: "Large-scale cluster management at Google with Borg", text: "用 Borg 在 Google 做大规模集群管理"),
        .init(
          source:
            "Google’s Borg system is a cluster manager that runs hundreds of thousands of jobs, from many thousands "
            + "of different applications, across a number of clusters each with up to tens of thousands of machines.",
          text: "Google 的 Borg 系统是一个集群管理器，运行着来自数千个不同应用的数十万个作业，分布在多个集群上，每个集群多达数万台机器。"),
        .init(
          source:
            "It achieves high utilization by combining admission control, efficient task-packing, over-commitment, "
            + "and machine sharing with process-level performance isolation.",
          text: "它把准入控制、高效的任务装箱、超额分配，以及带进程级性能隔离的机器共享结合起来，实现了很高的利用率。"),
      ])
  }
}
