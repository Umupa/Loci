/// One thing a learner wants to learn, and what a good mentor makes of it.
struct Scenario: Hashable, Sendable {
  let id: String
  /// What the learner types on the start page.
  let opening: String
  /// Who the learner is, for the judge to read the lessons as.
  let learner: String
  /// Hosts, or a host and path prefix, whose pages count as first-hand.
  let firstParty: [String]
  /// A question about the material, asked once the first lesson is written.
  let probe: String
  let lessons: ClosedRange<Int>
  /// How long the mentor gets for its first turn before it is stopped.
  let minutes: Int

  static let engineer =
    "Backend/infrastructure engineer, six years of Go and Linux in production, comfortable with Docker, "
    + "containers and basic networking; reads English technical docs fluently."

  /// The Mentor scenarios of 0.11's evaluation, so scores compare.
  static let all = [
    Scenario(
      id: "k8s-scheduling", opening: "I want to understand how the Kubernetes scheduler picks a node for a pod.",
      learner: engineer, firstParty: ["kubernetes.io", "github.com/kubernetes"],
      probe:
        "What exactly is the difference between the Filter and Score extension points, and where in the "
        + "scheduling cycle does PreFilter run?",
      lessons: 4...20, minutes: 18),
    Scenario(
      id: "sqlite-wal", opening: "Teach me SQLite's WAL mode properly.", learner: engineer, firstParty: ["sqlite.org"],
      probe:
        "What does a checkpoint do to the WAL file, and why can a long-running reader stop the WAL from being reset?",
      lessons: 3...15, minutes: 18),
    Scenario(
      id: "firecracker-paper", opening: "I want to read the Firecracker NSDI'20 paper with you.", learner: engineer,
      firstParty: [
        "usenix.org", "arxiv.org", "github.com/firecracker-microvm", "amazon.science", "firecracker-microvm.github.io",
      ],
      probe: "Why did the authors not just use QEMU, and what did they give up by writing their own VMM?",
      lessons: 4...20, minutes: 18),
  ]
}
