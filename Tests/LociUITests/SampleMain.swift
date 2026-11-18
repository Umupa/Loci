import Foundation
import LociModel

@testable import LociUI

/// The main conversation the design draws: last night's talk about Pingora, finishing it, and this morning
/// asking for videos on io_uring.
extension SampleLibrary {
  /// With `working`, Loci is still saving the videos it found and has not answered yet.
  func mainConversation(working: Bool = false) -> Conversation {
    var entropy = Sample.Seeded(state: 501)
    var entries: [Conversation.Entry] = []
    func stamp(_ date: Date) -> Timestamp {
      Timestamp(millisecondsSince1970: Int64(date.timeIntervalSince1970 * 1000))
    }
    func message(_ date: Date, _ body: Message.Body) -> Message {
      Message(id: EntityID(at: date, entropy: &entropy), at: stamp(date), body: body)
    }
    func say(_ date: Date, _ body: Message.Body) { entries.append(.message(message(date, body))) }
    func ask(_ date: Date, _ text: String) { say(date, .prompt(Prompt(text: text, purpose: .chat))) }
    func happen(_ date: Date, _ kind: WorldEvent.Kind) {
      entries.append(.event(WorldEvent(id: EntityID(at: date, entropy: &entropy), at: stamp(date), kind: kind)))
    }
    let night = Self.moment(daysAgo: 1, 23, 52)
    ask(night, "还在看 Pingora 那篇")
    say(night + 8, .reply("都快十二点了\n\n看到哪了"))
    ask(night + 40, "连接池那段")
    say(night + 52, .reply("那段是全篇最值的。看完去睡\n\n明天早上我把 NGINX 的 worker 模型画张图给你"))
    happen(Self.moment(daysAgo: 0, 0, 31), .finishedReading(article))
    let morning = Self.moment(daysAgo: 0, 9, 12)
    ask(morning, "帮我找几个讲 io_uring 的好视频")
    say(morning + 6, .reply("行，等我一下"))
    let uring = items.first { $0.title.hasPrefix("io_uring") } ?? video
    let found =
      [uring] + items.filter { ["Linux Systems Performance", "Turning the Database Inside Out"].contains($0.title) }
    guard !working else {
      happen(
        morning + 40,
        .saved(uring, job: Job(item: uring.id, stage: .transcribe, state: .running(progress: Fraction(0.4)))))
      let prompt = message(morning + 50, .prompt(Prompt(text: "先看哪个？", purpose: .chat)))
      return Conversation(
        ref: .main, entries: entries, turn: LiveTurn(startedAt: prompt.at, messages: [prompt]),
        context: ContextUsage(used: 41_000, window: 200_000))
    }
    for (index, item) in found.enumerated() { happen(morning + 60 + Double(index), .saved(item, job: nil)) }
    say(morning + 70, .reply("存好了\n\n第一个必看，作者本人讲的。第三个我犹豫了一下，还是留着"))
    return Conversation(ref: .main, entries: entries, turn: nil, context: ContextUsage(used: 41_000, window: 200_000))
  }
}
