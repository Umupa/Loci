import Foundation
import LociModel
import Testing

@testable import LociHost

/// The transcript agent on this Mac's real pi. Skipped unless `LOCI_TEXT_LIVE=1`; spends a little of
/// whatever model pi is set up to use, and prints what came back.
@Suite(
  .serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCI_TEXT_LIVE"] == "1"), .timeLimit(.minutes(10)))
struct TranscriptAgentLiveTests {
  static let sentences = [
    "Today I want to talk about how a scheduler decides where a pod runs.",
    "Every pod that has no node yet goes into a queue.",
    "The scheduler takes one pod at a time from that queue.",
    "First it filters the nodes that cannot run the pod at all.",
    "A node is filtered out when it lacks the CPU or memory the pod requests.",
    "It is also filtered out when the pod does not tolerate one of its taints.",
    "What is left after filtering is called the feasible set.",
    "If the feasible set is empty, the pod stays pending.",
    "Then comes scoring, which is about preference rather than possibility.",
    "Each scoring plugin gives every feasible node a number from zero to a hundred.",
    "One plugin prefers nodes with the image already pulled.",
    "Another spreads pods of the same service across zones.",
    "The scores are weighted and summed, and the highest node wins.",
    "Ties are broken at random, so that load spreads out.",
    "Then the scheduler reserves the resources on that node in its cache.",
    "Binding happens asynchronously, so the next pod does not wait for the API server.",
    "This is where an interesting failure mode appears.",
    "If binding fails, the reservation has to be undone.",
    "Otherwise the cache believes resources are used that are actually free.",
    "Now let's talk about scale.",
    "In a cluster of five thousand nodes, scoring every node is expensive.",
    "So the scheduler only looks at a percentage of nodes once it has found enough feasible ones.",
    "By default that percentage shrinks as the cluster grows.",
    "This trades a slightly worse placement for much lower latency.",
    "Most clusters never notice the difference.",
    "Preemption is the last piece.",
    "When a high priority pod cannot be placed, the scheduler looks for lower priority pods to evict.",
    "It picks the node where evicting the fewest, least important pods makes room.",
    "Preemption is graceful, so the pod still waits for the victims to terminate.",
    "And that is the whole loop: queue, filter, score, reserve, bind.",
  ]

  @Test func aThirtySentenceTranscriptIsTranslatedAndOutlined() async throws {
    let transcript = try Transcript(
      language: "en", origin: .platform,
      segments: Self.sentences.enumerated().map { index, text in
        try Transcript.Segment(start: .seconds(index * 4), end: .seconds(index * 4 + 4), text: text)
      })
    let installed = InstalledAgents(tool: nil)
    let writer = AgentTranscriptAgent(runtime: Runtime(provider: .pi), agents: { await installed.driver(for: $0) })
    let clock = ContinuousClock()

    let started = clock.now
    let translation = try await writer.translate(transcript, into: "zh-Hans")
    let translated = clock.now - started
    let outline = try await writer.outline(transcript, title: "How the Kubernetes scheduler works")
    let outlined = clock.now - started - translated

    #expect(translation.fits(transcript))
    #expect(!outline.chapters.isEmpty)
    let report = [
      "LIVE translation \(translated)", translation.lines.prefix(5).joined(separator: "\n"),
      "LIVE outline \(outlined)",
      outline.chapters.map { "chapter \($0.start) \($0.title)" }.joined(separator: "\n"),
      outline.highlights.map { "highlight \($0.span.start)-\($0.span.end ?? .zero) \($0.title): \($0.reason)" }
        .joined(separator: "\n"),
    ].joined(separator: "\n")
    Issue.record(Comment(rawValue: report), severity: .warning)
  }

  @Test func anArticlesPassagesAreTranslatedKeepingTheirMarkdown() async throws {
    let passages = [
      "# The Tail at Scale",
      "Systems that respond to user actions **quickly** (within 100ms) feel more fluid than those that take longer.",
      "See [the paper](https://research.google/pubs/pub40801/) and run `sysctl -a` to compare.",
      "The fan-out math is simple: $p = 1 - 0.99^{100}$, about 63%.",
    ]
    let installed = InstalledAgents(tool: nil)
    let writer = AgentTranscriptAgent(runtime: Runtime(provider: .codex), agents: { await installed.driver(for: $0) })

    let lines = try await writer.translate(passages: passages, into: "zh-Hans")

    #expect(lines.count == passages.count)
    #expect(lines[0].hasPrefix("# "))
    #expect(lines[1].contains("**"))
    #expect(lines[2].contains("](https://research.google/pubs/pub40801/)"))
    #expect(lines[2].contains("`sysctl -a`"))
    #expect(lines[3].contains("$p = 1 - 0.99^{100}$"))
    Issue.record(Comment(rawValue: "LIVE passages\n" + lines.joined(separator: "\n")), severity: .warning)
  }
}
