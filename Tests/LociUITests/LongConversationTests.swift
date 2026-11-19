import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// C-11: a long conversation keeps showing its messages while questions follow one another, each answered
/// at length and followed to its end.
@MainActor
struct LongConversationTests {
  @Observable final class Feed {
    var conversation: Conversation
    init(_ conversation: Conversation) { self.conversation = conversation }
  }

  private struct Window: View {
    let feed: Feed

    var body: some View {
      ConversationView(
        conversation: feed.conversation, draft: .constant(nil), revealPassage: { _ in },
        send: { (_: String, _: Passage?) async throws(HostError) -> Done in Done() }, stop: {})
    }
  }

  private static func conversation(_ said: [Message], turn: LiveTurn? = nil) -> Conversation {
    Conversation(ref: .main, entries: said.map { .message($0) }, turn: turn)
  }

  private static func reply(_ question: Int, sections: Int) -> String {
    (1...sections).map { section in
      """
      ## 第 \(question).\(section) 节

      `strip` 去掉两端的空白，行内公式 $x^2$。

      - 一
      - 二

      ```python
      print("\(question)-\(section)")
      ```
      """
    }.joined(separator: "\n\n")
  }

  @Observable final class ReplyFeed {
    var paragraphs = ["先说结论。"]
  }

  private struct ReplyBubbles: View {
    static let inset: CGFloat = 20
    let feed: ReplyFeed

    var body: some View {
      let paragraphs = feed.paragraphs
      let positions = BubbleLayout.positions(paragraphs.map { _ in .loci })
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(paragraphs.indices, id: \.self) { index in
          BubbleRow(speaker: .loci, position: positions[index] ?? .alone, turn: false) {
            Text(verbatim: paragraphs[index])
          }
          .transition(.identity)
        }
      }
      .animatingArrivals(paragraphs.count)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(Self.inset)
      .background(Palette.canvas)
    }
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func aStreamingReplyShowsOnlyOneAvatarWhileANewBubbleArrives(appearance: Snapshot.Appearance) async throws {
    let feed = ReplyFeed()
    let avatar = NSImage(size: CGSize(width: 30, height: 30), flipped: false) { rect in
      NSColor.green.setFill()
      rect.fill()
      return true
    }
    let view = ReplyBubbles(feed: feed).environment(\.lociFace, .picture(avatar))
    var initialAvatarRow: Int?

    try await Snapshot.render(
      view, named: "talk-streaming-avatar", size: CGSize(width: 320, height: 160), appearance: appearance
    ) { window in
      guard let content = window.contentView else { return false }
      let avatars = Self.avatarRows(in: content)
      if let initialAvatarRow {
        guard avatars.contains(where: { $0 > initialAvatarRow }) else { return false }
        #expect(avatars.count == 1)
        return true
      }
      guard let firstAvatar = avatars.first else { return false }
      initialAvatarRow = firstAvatar
      feed.paragraphs.append("然后看例子。")
      return false
    }
  }

  private static func avatarRows(in view: NSView) -> [Int] {
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return [] }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let x = Int((ReplyBubbles.inset + TalkScale.main.face / 2) * CGFloat(bitmap.pixelsWide) / view.bounds.width)
    var rows: [Int] = []
    var inside = false
    for y in 0..<bitmap.pixelsHigh {
      guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
      let green = color.greenComponent - max(color.redComponent, color.blueComponent) > 0.08
      if green && !inside { rows.append(y) }
      inside = green
    }
    return rows
  }

  @Test func aLongConversationKeepsShowingItsMessagesWhileQuestionsFollowOneAnother() async throws {
    let sample = try Sample(problems: false)
    var clock: Int64 = 1_763_400_000_000
    func message(_ body: Message.Body) -> Message {
      clock += 1000
      return Message(id: EntityID(), at: Timestamp(millisecondsSince1970: clock), body: body)
    }
    var history = (1...30).flatMap { question in
      [
        message(.prompt(Prompt(text: "问题 \(question)", purpose: .chat))),
        message(.reply(Self.reply(question, sections: question % 3 + 1))),
      ]
    }
    let feed = Feed(Self.conversation(history))
    let size = CGSize(width: 420, height: 800)
    let host = NSHostingView(
      rootView: Window(feed: feed).frame(width: size.width, height: size.height)
        .lociHost(FakeHost(sample)))
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(300))

    var blank: [Int] = []
    for question in 31...42 {
      let asked = message(.prompt(Prompt(text: "R4-ACK-\(question)", purpose: .chat)))
      let answer = Self.reply(question, sections: question % 3 == 0 ? 40 : 3)
      let id = EntityID()
      var end = answer.startIndex
      repeat {
        end = answer.index(end, offsetBy: 80, limitedBy: answer.endIndex) ?? answer.endIndex
        let partial = Message(id: id, at: asked.at, body: .reply(String(answer[..<end])))
        feed.conversation = Self.conversation(
          history, turn: LiveTurn(startedAt: asked.at, messages: [asked, partial]))
        try await Task.sleep(for: .milliseconds(10))
      } while end < answer.endIndex
      history += [asked, Message(id: id, at: asked.at, body: .reply(answer))]
      feed.conversation = Self.conversation(history)
      try await Task.sleep(for: .milliseconds(300))
      if Self.isBlank(host) { blank.append(question) }
    }

    #expect(blank.isEmpty)
  }

  /// Whether the part of the window above the input field has nothing drawn in it.
  private static func isBlank(_ host: NSView) -> Bool {
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return true }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let paper = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 2) else { return true }
    for y in stride(from: bitmap.pixelsHigh / 8, to: bitmap.pixelsHigh * 6 / 10, by: 4) {
      for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
        guard let color = bitmap.colorAt(x: x, y: y) else { continue }
        let difference =
          abs(color.redComponent - paper.redComponent) + abs(color.greenComponent - paper.greenComponent)
          + abs(color.blueComponent - paper.blueComponent)
        if difference > 0.3 { return false }
      }
    }
    return true
  }
}
