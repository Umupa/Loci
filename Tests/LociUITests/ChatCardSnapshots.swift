import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// C-S3 to C-S6 and C-S8: document cards, link cards and library cards in the conversation, in light and
/// dark.
@MainActor
@Suite(.serialized, .onStage)
struct ChatCardSnapshots {
  static let document = """
    ````loci-doc
    # jailer 隔离了什么

    #### 有没有 jailer，差在哪

    | 隔离 | 没有 jailer | 有 jailer |
    |---|---|---|
    | 文件 | 宿主整个根目录 | chroot 到 `/srv/jailer/…` |
    | 进程 | 宿主的 PID 空间 | 新的 PID 命名空间 |
    | 身份 | `root` | 降到 `uid 123` |
    | 资源 | 不限 | cgroup 限 CPU 与内存 |

    打个比方：Firecracker 是一间屋子，虚拟机关在屋里；jailer 是把这间屋子再搬进一栋没有门的楼里。

    #### 启动长什么样

    ```sh
    jailer --id vm-42 --exec-file /usr/bin/firecracker --uid 123 --gid 100
    ```
    ````
    """

  /// The design's conversation: a conclusion and its document, three projects as a stack, a link with no
  /// picture, and an article Loci wrote and saved.
  static func conversation(note: Item) -> (Conversation, document: TalkRow.ID) {
    var entropy = Sample.Seeded(state: 7)
    let start: Int64 = 1_763_337_600_000
    var second: Int64 = 0
    func message(_ body: Message.Body) -> Message {
      second += 4
      let at = Timestamp(millisecondsSince1970: start + second * 1000)
      return Message(id: EntityID(at: at.date, entropy: &entropy), at: at, body: body)
    }
    let answer = message(
      .reply(
        "就是在 Firecracker 进程外面再包一层：chroot、新的命名空间、cgroup，最后降成普通用户。\n\n" + document))
    let messages = [
      message(.prompt(Prompt(text: "Firecracker 那篇说的 jailer，到底隔离了什么", purpose: .chat))), answer,
      message(.prompt(Prompt(text: "有什么类似的项目可以对照着读", purpose: .chat))),
      message(
        .reply(
          """
          挑了三个，都是 microVM 沙箱，和 CubeSandbox 一个路子。

          \(SampleLinks.firecracker.absoluteString)
          \(SampleLinks.e2b.absoluteString)
          [kata](\(SampleLinks.kata.absoluteString))

          还有一篇讲隔离为什么是一摞：

          \(SampleLinks.bare.absoluteString)
          """)),
      message(.prompt(Prompt(text: "好，把 envd 和 cube-agent 对照着拆一遍存进去", purpose: .chat))),
      message(.reply("写好了，放进资料库了。")), message(.savedItem(note.id)),
    ]
    return (
      Conversation(ref: .main, entries: messages.map { .message($0) }, turn: nil),
      TalkRow.ID(message: answer.id, part: 1)
    )
  }

  static func scene(_ library: SampleLibrary, note: Item, opened open: Bool) -> some View {
    let (conversation, row) = conversation(note: note)
    let opened = ReplyPiece.pieces(in: document).compactMap { if case .document(let shown) = $0 { shown } else { nil } }
    return ConversationView(
      conversation: conversation, draft: .constant(nil), revealPassage: { _ in },
      send: { (_: String, _: Passage?) async throws(HostError) -> Done in Done() }, stop: {}
    )
    .showingDocuments(opened: open ? opened.first.map { (row, $0) } : nil)
  }

  static func library() throws -> (SampleLibrary, Item) {
    var library = try SampleLibrary()
    let note = try Item(id: EntityID(), kind: .article, title: "envd 与 cube-agent", authors: [Item.companionCredit])
    library.items.append(note)
    return (library, note)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func cardsInTheConversation(appearance: Snapshot.Appearance) async throws {
    let (library, note) = try Self.library()
    try await Self.shoot("chat-cards", Self.scene(library, note: note, opened: false), library, appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func anOpenDocument(appearance: Snapshot.Appearance) async throws {
    let (library, note) = try Self.library()
    try await Self.shoot("chat-document", Self.scene(library, note: note, opened: true), library, appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func spreadLinkCards(appearance: Snapshot.Appearance) async throws {
    let (library, _) = try Self.library()
    let pieces = VStack(alignment: .leading, spacing: 18) {
      LinkCards(links: [SampleLinks.firecracker, SampleLinks.e2b, SampleLinks.kata], spread: true)
    }
    .padding(28)
    .frame(width: 600)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Palette.canvas)
    try await Self.shoot("chat-card-pieces", pieces, library, appearance, size: CGSize(width: 600, height: 440))
  }

  private static func shoot(
    _ name: String, _ view: some View, _ library: SampleLibrary, _ appearance: Snapshot.Appearance,
    size: CGSize = CGSize(width: 760, height: 1400)
  ) async throws {
    let activity = Activity()
    let covers = Covers()
    let previews = LinkPreviews()
    let shown =
      view
      .environment(\.covers, covers)
      .environment(\.linkPreviews, previews)
      .environment(\.standIns, StandIns(conversationAt: Date(timeIntervalSince1970: 1_763_337_700)))
      .lociHost(FakeHost(try Sample(problems: false), library: library, activity: activity))
    let quiet = Quiet(activity)
    let file = try await Snapshot.render(
      shown, named: name, size: size, appearance: appearance,
      until: { _ in quiet.settled() && previews.image(of: SampleLinks.firecracker) != nil }, steady: true)
    #expect(try Data(contentsOf: file).count > 10_000)
  }
}
