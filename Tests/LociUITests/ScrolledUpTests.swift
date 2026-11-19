import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// C-11: someone who scrolls up while Loci answers can keep reading; the conversation does no work frame by
/// frame while they do.
@MainActor
struct ScrolledUpTests {
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

  private final class CountingHost<Content: View>: NSHostingView<Content> {
    var layouts = 0

    override func layout() {
      layouts += 1
      super.layout()
    }
  }

  /// Nothing typed yet, a line, or several lines waiting in the field.
  nonisolated static let drafts = ["", "这一段我还想再问问它和上面那个有什么区别", "第一行想问的\n第二行补充一下\n第三行"]

  @Test(arguments: drafts)
  func scrollingUpWhileLociAnswersLeavesNothingMovingFrameByFrame(draft: String) async throws {
    let sample = try Sample(problems: false)
    var clock: Int64 = 1_763_400_000_000
    func message(_ body: Message.Body) -> Message {
      clock += 1000
      return Message(id: EntityID(), at: Timestamp(millisecondsSince1970: clock), body: body)
    }
    let history = (1...60).flatMap { question in
      [
        message(.prompt(Prompt(text: "问题 \(question)", purpose: .chat))),
        message(.reply((1...4).map { "第 \(question).\($0) 段，说得长一些，让每个气泡都有几行字。" }.joined(separator: "\n\n"))),
      ]
    }
    let asked = message(.prompt(Prompt(text: "再讲讲", purpose: .chat)))
    let answer = message(.reply("先说结论。\n\n再说原因。"))
    func growing(_ more: Int) -> Message {
      Message(
        id: answer.id, at: answer.at,
        body: .reply((0...more).map { "第 \($0) 段，接着往下写。" }.joined(separator: "\n\n")))
    }
    let feed = Feed(
      Conversation(
        ref: .main, entries: history.map { .message($0) },
        turn: LiveTurn(startedAt: asked.at, messages: [asked, answer])))
    let size = CGSize(width: 420, height: 600)
    let host = CountingHost(
      rootView: Window(feed: feed).frame(width: size.width, height: size.height).lociHost(FakeHost(sample)))
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    try await eventually("the conversation to show its end") {
      guard let scroll = Self.scrollView(in: host), let document = scroll.documentView else { return false }
      return document.frame.height > 2000 && scroll.contentView.bounds.minY > 1000
    }

    if !draft.isEmpty {
      let field = try #require(Self.textField(in: host))
      window.makeFirstResponder(field)
      let editor = try #require(field.currentEditor() as? NSTextView)
      editor.insertText(draft, replacementRange: NSRange(location: NSNotFound, length: 0))
      try await eventually("the draft to be in the field") { field.stringValue == draft }
    }

    let scroll = try #require(Self.scrollView(in: host))
    let bottom = scroll.contentView.bounds.minY
    for phase in [CGScrollPhase.began] + Array(repeating: .changed, count: 20) + [.ended] {
      let event = CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: phase == .ended ? 0 : 150, wheel2: 0,
        wheel3: 0)
      event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
      if let event, let scrolled = NSEvent(cgEvent: event) { scroll.scrollWheel(with: scrolled) }
      try await Task.sleep(for: .milliseconds(16))
    }
    for more in 1...10 {
      feed.conversation = Conversation(
        ref: .main, entries: history.map { .message($0) },
        turn: LiveTurn(startedAt: asked.at, messages: [asked, growing(more)]))
      try await Task.sleep(for: .milliseconds(67))
    }
    try await eventually("the conversation to stay where it was scrolled to") {
      scroll.contentView.bounds.minY < bottom - 1000
    }

    var still = false
    let deadline = ContinuousClock.now + .seconds(10)
    while !still && ContinuousClock.now < deadline {
      host.layouts = 0
      try await Task.sleep(for: .milliseconds(500))
      still = host.layouts < 3
    }
    #expect(still, "laid out \(host.layouts) times in half a second")
  }

  private static func textField(in view: NSView) -> NSTextField? {
    if let field = view as? NSTextField, field.isEditable { return field }
    return view.subviews.lazy.compactMap(textField(in:)).first
  }

  private static func scrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    return view.subviews.lazy.compactMap(scrollView(in:)).first
  }
}
