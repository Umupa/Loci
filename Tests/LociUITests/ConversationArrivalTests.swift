import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// A conversation that arrives after its page is on screen opens at its latest message, as one that was
/// already there does.
@MainActor
@Suite(.onStage(alone: true))
struct ConversationArrivalTests {
  @Observable final class Feed {
    var conversation: Conversation?
  }

  private struct Window: View {
    let feed: Feed

    var body: some View {
      ConversationView(
        conversation: feed.conversation, draft: .constant(nil), revealPassage: { _ in },
        send: { (_: String, _: Passage?) async throws(HostError) -> Done in Done() }, stop: {},
        tail: { Color(red: 1, green: 0, blue: 0).frame(height: 24) })
    }
  }

  private static func conversation() -> Conversation {
    var clock: Int64 = 1_763_400_000_000
    let said = (1...30).flatMap { question in
      [
        Message.Body.prompt(Prompt(text: "问题 \(question)", purpose: .chat)),
        .reply(String(repeating: "这是第 \(question) 个回答里的一句话。", count: 12)),
      ]
    }.map { body in
      clock += 1000
      return Message(id: EntityID(), at: Timestamp(millisecondsSince1970: clock), body: body)
    }
    return Conversation(ref: .main, entries: said.map { .message($0) }, turn: nil)
  }

  @Test func aConversationThatArrivesLateOpensAtItsLatestMessage() async throws {
    let feed = Feed()
    let size = CGSize(width: 700, height: 800)
    let host = NSHostingView(
      rootView: Window(feed: feed).frame(width: size.width, height: size.height)
        .lociHost(FakeHost(try Sample(problems: false))))
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(500))

    feed.conversation = Self.conversation()
    try await Task.sleep(for: .seconds(1))

    #expect(Self.showsEnd(host))
  }

  /// Whether the red mark after the last message is on screen.
  private static func showsEnd(_ host: NSView) -> Bool {
    host.layoutSubtreeIfNeeded()
    guard let bitmap = try? Snapshot.bitmap(of: host) else { return false }
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
      for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
        guard let color = bitmap.colorAt(x: x, y: y) else { continue }
        if color.redComponent > 0.9, color.greenComponent < 0.2, color.blueComponent < 0.2 { return true }
      }
    }
    return false
  }
}
