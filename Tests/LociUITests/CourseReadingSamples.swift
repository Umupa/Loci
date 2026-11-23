import Foundation
import LociModel

@testable import LociUI

/// The Raft course from the design, being read.
enum ReadingSamples {
  static let addresses = [
    "https://raft.github.io/raft.pdf", "https://www.youtube.com/watch?v=vYp4LYbnnW8",
    "https://web.stanford.edu/~ouster/cgi-bin/papers/OngaroPhD.pdf", "https://github.com/etcd-io/raft",
    "https://etcd.io/docs/v3.5/learning/api_guarantees/", "https://lamport.azurewebsites.net/pubs/paxos-simple.pdf",
  ]

  static let sources: [SourceShown] = BuilderSamples.sources.enumerated().map { index, source in
    var shown = source
    shown.url = URL(string: addresses[index])
    return shown
  }

  static let markdown = """
    五台机器，每台都可能宕机、变慢、丢消息。它们要对同一串命令达成一致：同样的顺序，一条不多，一条不少。只要还有多数活着，系统就得接着往前走。[原论文第 2 节](https://raft.github.io/raft.pdf#page=2)

    你在 etcd 里写下一个键，背后就是这件事：这条写入先追加进领导者的日志，复制到多数，才算数。客户端收到成功的那一刻，五台里至少三台的磁盘上已经有它。[etcd 的保证](https://etcd.io/docs/v3.5/learning/api_guarantees/#:~:text=linearizable)

    另外两台呢？它们可能正在重启，可能网线被拔了。等它们回来，领导者会把缺的那一段补给它们。慢的机器不拖累整体，这就是多数派的价值。[领导者补日志](https://github.com/etcd-io/raft/blob/4abf9f2/raft.go#L560-L590)

    > 难的不是复制，是在谁都可能掉线的时候，仍然只有一个版本的历史。

    后面九课，都在回答同一个问题的不同侧面：怎么保证只有一个版本。先从最底下的那块砖开始，多数派为什么一定有交集。
    """

  /// The words highlighted on the first lesson.
  static let highlighted = "慢的机器不拖累整体，这就是多数派的价值"

  static func rows(current: Int, written: Int = 3, writing: Int? = 3) -> [LessonThread.Row] {
    BuilderSamples.titles.enumerated().map { index, title in
      let mark: LessonThread.Mark =
        index == writing ? .writing : index >= written ? .planned : index < current ? .read : .written
      return LessonThread.Row(
        id: BuilderSamples.lessonIDs[index], title: title, mark: mark, current: index == current)
    }
  }

  static func first(nextWriting: Bool = false) -> ReadingShown {
    let ids = BuilderSamples.lessonIDs
    let writing = nextWriting ? 1 : 3
    return ReadingShown(
      course: BuilderSamples.raft, title: "Raft", lessons: rows(current: 0, written: writing, writing: writing),
      sources: sources,
      lesson: .written(ids[0], title: BuilderSamples.titles[0], minutes: 8, markdown: markdown))
  }

  static func unwritten() -> ReadingShown {
    let next = 3
    return ReadingShown(
      course: BuilderSamples.raft, title: "Raft", lessons: rows(current: next, writing: nil), sources: sources,
      lesson: .unwritten(BuilderSamples.lessonIDs[next], title: BuilderSamples.titles[next], writing: false))
  }
}

/// What was said about the course, as its conversation.
enum CourseConversation {
  /// Lines said in turn, a second apart; `thinking` adds a turn under way in which Loci is thinking.
  static func of(_ lines: [(loci: Bool, text: String)], thinking: Bool = false) -> Conversation {
    var entropy = Sample.Seeded()
    func message(_ second: Double, _ body: Message.Body) -> Message {
      let date = Date(timeIntervalSince1970: 1_763_340_000 + second)
      return Message(
        id: EntityID(at: date, entropy: &entropy),
        at: Timestamp(millisecondsSince1970: Int64(date.timeIntervalSince1970 * 1000)), body: body)
    }
    let entries = lines.enumerated().map { index, line in
      Conversation.Entry.message(
        message(Double(index), line.loci ? .reply(line.text) : .prompt(Prompt(text: line.text, purpose: .chat))))
    }
    let turn =
      thinking
      ? LiveTurn(
        startedAt: Timestamp(millisecondsSince1970: 1_763_340_100_000),
        messages: [message(100, .thinking("先找原论文和 etcd 的实现。"))]) : nil
    return Conversation(ref: .course(BuilderSamples.raft), entries: entries, turn: turn)
  }

  static let sample = of([
    (false, "慢的那两台回来时，领导者怎么知道该从哪补？"), (true, "它给每台记着一个 nextIndex，回来的那台拒绝一次，它就往前退一格再试。\n\n第五课会细讲这个退的过程。"),
  ])
}
