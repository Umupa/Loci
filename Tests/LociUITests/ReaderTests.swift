import AppKit
import LociModel
import Testing

@testable import LociUI

/// The reader opens where it was left, stays put when the text is revised, and says where the reader is.
@MainActor
struct ReaderTests {
  /// About twenty thousand characters in three hundred paragraphs.
  static let long = (1...300).map { "第 \($0) 段：调度器先过滤不合适的节点，再给剩下的节点打分，最后把任务绑定到得分最高的节点上。为什么分两步？" }
    .joined(separator: "\n\n")

  final class Heard {
    var moves: [TextQuote] = []
    var ends = 0
  }

  static func reader(heard: Heard) -> (ReaderCoordinator, NSScrollView, NSWindow) {
    let coordinator = ReaderCoordinator(
      events: ReaderEvents(moved: { heard.moves.append($0) }, reachedEnd: { heard.ends += 1 }),
      settle: .milliseconds(50))
    let scrollView = coordinator.makeScrollView()
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 900, height: 700), styleMask: [.titled], backing: .buffered,
      defer: false)
    window.contentView = scrollView
    return (coordinator, scrollView, window)
  }

  static func paragraph(_ number: Int, in text: String) throws -> TextQuote {
    let range = try #require(text.range(of: "第 \(number) 段"))
    return try TextQuote(quoting: range, in: text)
  }

  @Test func theReaderOpensAtTheParagraphItWasLeftAt() throws {
    let (coordinator, _, window) = Self.reader(heard: Heard())
    defer { window.orderOut(nil) }
    let text = ReadingText(markdown: Self.long)

    coordinator.show(text, from: try Self.paragraph(200, in: text.plain))

    #expect(coordinator.topQuote()?.text.hasPrefix("第 200 段") == true)
  }

  @Test func aRevisedTextKeepsTheReaderOnTheSameParagraph() throws {
    let (coordinator, _, window) = Self.reader(heard: Heard())
    defer { window.orderOut(nil) }
    let text = ReadingText(markdown: Self.long)
    coordinator.show(text, from: try Self.paragraph(120, in: text.plain))

    coordinator.show(ReadingText(markdown: "# 修订\n\n开头加了一段新的引言。\n\n" + Self.long), from: nil)

    #expect(coordinator.topQuote()?.text.hasPrefix("第 120 段") == true)
  }

  @Test func narrowingTheWindowKeepsTheReaderOnTheSameParagraph() throws {
    let (coordinator, _, window) = Self.reader(heard: Heard())
    defer { window.orderOut(nil) }
    let text = ReadingText(markdown: Self.long)
    coordinator.show(text, from: try Self.paragraph(150, in: text.plain))

    window.setContentSize(CGSize(width: 600, height: 700))

    #expect(coordinator.topQuote()?.text.hasPrefix("第 150 段") == true)
  }

  @Test func reachingTheEndIsToldOnce() throws {
    let heard = Heard()
    let (coordinator, scrollView, window) = Self.reader(heard: heard)
    defer { window.orderOut(nil) }
    coordinator.show(ReadingText(markdown: Self.long), from: nil)
    #expect(heard.ends == 0)

    let textView = try #require(scrollView.documentView as? ReaderTextView)
    for _ in 0..<100 where heard.ends == 0 {
      scrollView.contentView.scroll(to: CGPoint(x: 0, y: textView.frame.height))
      textView.layOutViewport()
    }

    #expect(heard.ends == 1)
  }

  @Test func aShortTextIsReadAsSoonAsItIsShown() {
    let heard = Heard()
    let (coordinator, _, window) = Self.reader(heard: heard)
    defer { window.orderOut(nil) }

    coordinator.show(ReadingText(markdown: "只有一段。"), from: nil)

    #expect(heard.ends == 1)
  }

  @Test func whereTheReaderSettlesIsRemembered() async throws {
    let heard = Heard()
    let (coordinator, scrollView, window) = Self.reader(heard: heard)
    defer { window.orderOut(nil) }
    let text = ReadingText(markdown: Self.long)
    coordinator.show(text, from: try Self.paragraph(50, in: text.plain))

    scrollView.contentView.scroll(to: CGPoint(x: 0, y: scrollView.documentVisibleRect.minY + 400))
    for _ in 0..<100 where heard.moves.isEmpty { try await Task.sleep(for: .milliseconds(50)) }

    let quote = try #require(heard.moves.last)
    #expect(quote.text.hasPrefix("第 5"))
    #expect(quote.range(in: text.plain) != nil)
  }
}
