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
    let mentor: Mentor

    var body: some View {
      ConversationView(
        mentor: mentor, conversation: feed.conversation, draft: .constant(nil), revealPassage: { _ in },
        send: { (_: String, _: Passage?) async throws(HostError) -> Done in Done() }, stop: {})
    }
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
    let feed = Feed(Conversation(mentor: sample.scheduling.id, messages: history, turn: nil))
    let size = CGSize(width: 420, height: 800)
    let host = NSHostingView(
      rootView: Window(feed: feed, mentor: sample.scheduling).frame(width: size.width, height: size.height)
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
        feed.conversation = Conversation(
          mentor: sample.scheduling.id, messages: history,
          turn: LiveTurn(startedAt: asked.at, messages: [asked, partial]))
        try await Task.sleep(for: .milliseconds(10))
      } while end < answer.endIndex
      history += [asked, Message(id: id, at: asked.at, body: .reply(answer))]
      feed.conversation = Conversation(mentor: sample.scheduling.id, messages: history, turn: nil)
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
