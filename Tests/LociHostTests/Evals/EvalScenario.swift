import Foundation

/// Something that happens in the pages a schedule reads, which a run should notice once.
struct EvalEvent: Hashable, Sendable {
  let id: String
  /// One sentence, for the report and the judge.
  let about: String
  /// Words any mention of it contains, in either language; matched without case.
  let keywords: [String]

  func isMentioned(in text: String) -> Bool {
    keywords.contains { text.localizedCaseInsensitiveContains($0) }
  }
}

/// One day of an eval: the pages as they are that evening, what is new in them, and what the person did first.
struct EvalDay: Sendable {
  enum Kind: Sendable {
    /// These events appear for the first time.
    case news([String])
    /// The pages are as they were the day before.
    case same
    /// Only changes that do not matter: typos, badges, version bumps, star counts.
    case noise
  }

  let kind: Kind
  let pages: EvalPageSet
  /// The event the person marks 「不想再看」 in the panel before this day's run.
  var hide: String?
}

/// What the local server answers on each path that evening.
struct EvalPageSet: Sendable {
  let releases: [String]
  let issues: [String]
  let commits: [String]

  /// The pages as HTML, by path.
  var pages: [String: String] {
    [
      "/releases": Self.page("Releases · TencentCloud/CubeSandbox", releases),
      "/issues": Self.page("Issues · TencentCloud/CubeSandbox", issues),
      "/commits": Self.page("Commits · TencentCloud/CubeSandbox/main", commits),
    ]
  }

  static func page(_ title: String, _ entries: [String]) -> String {
    let items = entries.map { "<li>\($0)</li>" }.joined(separator: "\n")
    return """
      <!doctype html><html lang="en"><head><meta charset="utf-8"><title>\(title)</title></head>
      <body><main><article><h1>\(title)</h1><ul>
      \(items)
      </ul></article></main></body></html>
      """
  }
}

/// A schedule followed for several days, and what each day should and should not leave behind.
struct EvalScenario: Sendable {
  enum Group: String, CaseIterable, Sendable {
    case quiet
    case repeated = "repeat"
  }

  let group: Group
  let events: [EvalEvent]
  let days: [EvalDay]
  /// Words that mark a change as noise.
  let noise: [String]

  func event(_ id: String) -> EvalEvent? { events.first { $0.id == id } }

  /// The events that appeared before `day` (counted from 0).
  func known(before day: Int) -> [EvalEvent] {
    days.prefix(day).flatMap { day -> [String] in
      if case .news(let ids) = day.kind { return ids }
      return []
    }
    .compactMap(event)
  }

  func news(on day: Int) -> [EvalEvent] {
    if case .news(let ids) = days[day].kind { return ids.compactMap(event) }
    return []
  }

  /// The event marked 「不想再看」 on or before `day`.
  func hidden(by day: Int) -> EvalEvent? {
    days.prefix(day + 1).compactMap(\.hide).last.flatMap(event)
  }

  static func of(_ group: Group) -> EvalScenario {
    switch group {
    case .quiet: quiet
    case .repeated: repeated
    }
  }
}

extension EvalScenario {
  static let noiseWords = ["typo", "badge", "bump", "stars", "错字", "徽章"]

  private static let v09 = "v0.9.0 — Snapshot restore drops from 1.8s to 0.6s (prefetching memory pages on resume)."
  private static let issue412 = "#412 Snapshot restore fails now and then on ARM hosts · opened"
  private static let older = [
    "v0.8.2 — Fix cgroup cleanup when a sandbox is killed.", "v0.8.0 — First public release.",
  ]
  private static let olderIssues = [
    "#398 Compare cold start with Firecracker · closed", "#350 Docs: install on Ubuntu · closed",
  ]
  private static let olderCommits = ["Merge #405: faster template copy", "Add arm64 CI runner"]

  /// Five evenings: news, the same pages, noise, news again, noise.
  static let quiet: EvalScenario = {
    let first = EvalPageSet(
      releases: [v09] + older, issues: [issue412] + olderIssues,
      commits: ["Prefetch memory pages on snapshot resume", "Release v0.9.0"] + olderCommits)
    let noisy = EvalPageSet(
      releases: first.releases, issues: first.issues,
      commits: ["Fix typo in README", "Update CI badge", "Bump golang.org/x/sys from 0.25.0 to 0.26.0"] + first.commits)
    let v010 = EvalPageSet(
      releases: ["v0.10.0 — virtio-fs shared folders between host and sandbox."] + first.releases,
      issues: ["#412 Snapshot restore fails now and then on ARM hosts · closed by #431"] + olderIssues,
      commits: ["Add virtio-fs shared folders (#431)", "Release v0.10.0"] + noisy.commits)
    let noisyAgain = EvalPageSet(
      releases: v010.releases, issues: v010.issues,
      commits: ["Bump actions/checkout from 4 to 5", "Fix typo in CONTRIBUTING", "README: 1.2k stars badge"]
        + v010.commits)
    return EvalScenario(
      group: .quiet,
      events: [
        EvalEvent(id: "v0.9", about: "v0.9.0 发布：快照恢复从 1.8s 降到 0.6s", keywords: ["v0.9", "0.9.0"]),
        EvalEvent(id: "#412", about: "#412 新开：ARM 上快照恢复偶尔失败", keywords: ["#412", "412"]),
        EvalEvent(
          id: "v0.10", about: "v0.10.0 发布：host 与沙箱之间的 virtio-fs 共享目录", keywords: ["v0.10", "0.10.0", "virtio-fs"]),
        EvalEvent(id: "#412 closed", about: "#412 被 #431 修好关闭", keywords: ["#431"]),
      ],
      days: [
        EvalDay(kind: .news(["v0.9", "#412"]), pages: first),
        EvalDay(kind: .same, pages: first),
        EvalDay(kind: .noise, pages: noisy),
        EvalDay(kind: .news(["v0.10", "#412 closed"]), pages: v010),
        EvalDay(kind: .noise, pages: noisyAgain),
      ],
      noise: noiseWords)
  }()

  /// Four evenings over the same pages: three things, a fourth, then the person hides one of them.
  static let repeated: EvalScenario = {
    let blog = "Blog: How CubeSandbox starts a sandbox in 60ms (cold start, measured on c7g)"
    let first = EvalPageSet(
      releases: [v09, blog] + older, issues: [issue412] + olderIssues,
      commits: ["Release v0.9.0"] + olderCommits)
    let second = EvalPageSet(
      releases: first.releases, issues: ["#420 Support GPU passthrough · opened"] + first.issues,
      commits: first.commits)
    let third = EvalPageSet(
      releases: first.releases,
      issues: ["#412 Snapshot restore fails now and then on ARM hosts · new comment: also seen on Graviton 4"]
        + ["#420 Support GPU passthrough · opened"] + olderIssues,
      commits: first.commits)
    return EvalScenario(
      group: .repeated,
      events: [
        EvalEvent(id: "A", about: "v0.9.0 发布", keywords: ["v0.9", "0.9.0"]),
        EvalEvent(id: "B", about: "#412：ARM 上快照恢复偶尔失败", keywords: ["#412", "412"]),
        EvalEvent(id: "C", about: "博客：60ms 冷启动", keywords: ["60ms", "60 ms", "冷启动", "cold start"]),
        EvalEvent(id: "D", about: "#420：支持 GPU 直通", keywords: ["#420", "420", "GPU"]),
      ],
      days: [
        EvalDay(kind: .news(["A", "B", "C"]), pages: first),
        EvalDay(kind: .news(["D"]), pages: second),
        EvalDay(kind: .same, pages: third, hide: "B"),
        EvalDay(kind: .same, pages: third),
      ],
      noise: noiseWords)
  }()
}
