import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// Items Loci put into the library, as cards in a conversation, in light and dark.
@MainActor
@Suite(.serialized, .onStage)
struct SavedItemsSnapshots {
  /// Three saved in a row with their covers and one still downloading, then an article Loci wrote, a paper with
  /// no cover, one that failed, and one deleted since.
  @Test(arguments: Snapshot.Appearance.allCases)
  func savedItems(appearance: Snapshot.Appearance) async throws {
    var library = try SampleLibrary()
    let note = try Item(id: EntityID(), kind: .article, title: "调度器怎么给 Pod 打分", authors: [LociAuthor.name])
    let borg = try Item(
      id: EntityID(), kind: .paper, title: "Large-scale cluster management at Google with Borg", authors: ["Verma"])
    library.items += [note, borg]
    let failed = try #require(library.items.first { $0.title == "Turning the Database Inside Out" })
    let uring = try #require(library.items.first { $0.title.hasPrefix("io_uring") })
    let said: [Message.Body] = [
      .prompt(Prompt(text: "把今天看的调度那几个存进资料库", purpose: .chat)),
      Self.save(1), .savedItem(library.video.id), Self.save(2), .savedItem(uring.id), Self.save(3),
      .savedItem(library.podcast.id),
      .reply("存好了。io_uring 那个还在下载"),
      .prompt(Prompt(text: "顺手把刚才聊的写成一篇笔记，再把 Kleppmann 那个也存一下", purpose: .chat)),
      Self.save(4), .savedItem(note.id), Self.save(5), .savedItem(borg.id), .savedItem(failed.id),
      .savedItem(EntityID()),
      .reply("笔记写好了。Kleppmann 那个 YouTube 拒绝了，得更新 yt-dlp"),
    ]
    let start: Int64 = 1_763_337_600_000
    let messages = said.enumerated().map { index, body in
      Message(id: EntityID(), at: Timestamp(millisecondsSince1970: start + Int64(index) * 4000), body: body)
    }
    let activity = Activity()
    let covers = Covers()
    let view = ConversationView(
      conversation: Conversation(ref: .main, entries: messages.map { .message($0) }, turn: nil),
      draft: .constant(nil), revealPassage: { _ in },
      send: { (_: String, _: Passage?) async throws(HostError) -> Done in Done() }, stop: {}
    )
    .environment(\.covers, covers)
    .environment(\.standIns, StandIns(conversationAt: Date(timeIntervalSince1970: TimeInterval(start / 1000) + 60)))
    .lociHost(FakeHost(try Sample(problems: false), library: library, activity: activity))
    let covered = [library.video.id, uring.id, library.podcast.id, failed.id]
    let quiet = Quiet(activity)
    let file = try await Snapshot.render(
      view, named: "saved-items", size: CGSize(width: 720, height: 980), appearance: appearance,
      until: { _ in quiet.settled() && covered.allSatisfy { covers.image(of: $0) != nil } }, steady: true)
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  private static func save(_ second: Int) -> Message.Body {
    .tool(
      ToolActivity(
        id: "\(second)", name: "Bash", kind: .execute, subject: "loci save", output: "", state: .succeeded))
  }
}
