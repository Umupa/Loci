import AppKit
import LociModel
import Testing

@testable import LociUI

/// The reader opens where it was left, stays put when the text is revised, and says where the reader is.
@MainActor
@Suite(.onStage)
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

  @Test func leavingTheReaderDismissesItsSelectionBar() async throws {
    let (coordinator, _, window) = Self.reader(heard: Heard())
    defer { window.orderOut(nil) }
    coordinator.events.passage = PassageActions(highlight: { _ in nil }, think: { _, _ in })
    coordinator.show(ReadingText(markdown: Self.long), from: nil)
    coordinator.select("调度器先过滤")
    try await eventually("the selection bar") { window.childWindows?.count == 1 }

    window.contentView = NSView()

    #expect(window.childWindows?.isEmpty != false)
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

  /// Long English sections of very different lengths, as a reference page has: what a jump into the
  /// middle lays out is far from what was estimated for it.
  static let reference = (1...40).map { section in
    "## Section \(section)\n\n"
      + (1...(section % 7 + 1)).map { paragraph in
        String(
          repeating: "Caches store responses so that later requests can be answered without the origin server. ",
          count: (section * paragraph) % 13 + 1)
      }.joined(separator: "\n\n")
  }.joined(separator: "\n\n")

  @Test(arguments: [0.2, 0.36, 0.5, 0.7])
  func jumpingIntoTheMiddleIsNotReachingTheEnd(share: Double) throws {
    let heard = Heard()
    let (coordinator, scrollView, window) = Self.reader(heard: heard)
    defer { window.orderOut(nil) }
    coordinator.show(ReadingText(markdown: Self.reference), from: nil)
    let textView = try #require(scrollView.documentView as? ReaderTextView)

    for _ in 0..<5 {
      let height = textView.frame.height - scrollView.contentView.bounds.height
      scrollView.contentView.scroll(to: CGPoint(x: 0, y: height * share))
      scrollView.reflectScrolledClipView(scrollView.contentView)
      textView.layOutViewport()
    }
    window.setContentSize(CGSize(width: 600, height: 700))
    window.setContentSize(CGSize(width: 1200, height: 500))

    #expect(heard.ends == 0)
  }

  @Test func picturesArrivingBeforeTheReaderHasAWidthKeepItsPlace() throws {
    let heard = Heard()
    let coordinator = ReaderCoordinator(
      events: ReaderEvents(moved: { heard.moves.append($0) }, reachedEnd: { heard.ends += 1 }),
      settle: .milliseconds(50))
    let scrollView = coordinator.makeScrollView()
    let markdown = "![调度](images/a.png)\n\n" + Self.long
    let picture = NSImage(size: NSSize(width: 200, height: 160), flipped: false) { _ in true }
    let plain = ReadingText(markdown: markdown)
    coordinator.show(plain, from: try Self.paragraph(150, in: plain.plain))

    coordinator.show(ReadingText(markdown: markdown, images: ["images/a.png": picture]), from: nil)
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 900, height: 700), styleMask: [.titled], backing: .buffered,
      defer: false)
    defer { window.orderOut(nil) }
    window.contentView = scrollView
    window.layoutIfNeeded()

    #expect(coordinator.topQuote()?.text.hasPrefix("第 150 段") == true)
  }

  /// A long text with one picture before paragraph 150, as the article reads before and after it arrives.
  static func illustrated() -> (markdown: String, picture: NSImage) {
    let paragraphs = (1...300).map { "第 \($0) 段：调度器先过滤不合适的节点，再给剩下的节点打分，最后把任务绑定到得分最高的节点上。为什么分两步？" }
    let markdown = (paragraphs[..<149] + ["![](images/k.png)"] + paragraphs[149...]).joined(separator: "\n\n")
    let picture = NSImage(size: NSSize(width: 600, height: 400), flipped: false) { _ in true }
    return (markdown, picture)
  }

  /// On a runner whose main thread lays out for other windows too, TextKit can correct its estimates a turn after
  /// the reader aligned the text, which reads as a move and is remembered; what is remembered last is still the
  /// picture's place, and that is what reopening uses.
  @Test func aPlaceAtAPictureIsKeptUntilThePictureArrivesAndIsWhatIsRemembered() async throws {
    let heard = Heard()
    let (coordinator, _, window) = Self.reader(heard: heard)
    defer { window.orderOut(nil) }
    let (markdown, picture) = Self.illustrated()
    let withPicture = ReadingText(markdown: markdown, images: ["images/k.png": picture])
    let at = (withPicture.plain as NSString).range(of: "\u{FFFC}")
    let place = try #require(withPicture.quote(at)?.quote)

    coordinator.show(ReadingText(markdown: markdown), from: place)
    #expect(coordinator.topQuote()?.text.hasPrefix("第 150 段") == true)
    window.setContentSize(CGSize(width: 700, height: 700))
    coordinator.show(withPicture, from: place)
    try await Task.sleep(for: .milliseconds(200))

    #expect(coordinator.topQuote()?.text == "\u{FFFC}")
    #expect(heard.moves.last.map { $0.text == "\u{FFFC}" } ?? true)
  }

  @Test func picturesArrivingOneByOneKeepThePlaceItWasOpenedAt() async throws {
    let heard = Heard()
    let (coordinator, _, window) = Self.reader(heard: heard)
    defer { window.orderOut(nil) }
    let pictures = (1...5).map { "![](images/\($0).png)" }
    let markdown = (pictures + (1...300).map { "第 \($0) 段：调度器先过滤不合适的节点，再给剩下的节点打分。" }).joined(separator: "\n\n")
    let picture = NSImage(size: NSSize(width: 600, height: 400), flipped: false) { _ in true }
    let first = ReadingText(markdown: markdown)
    let place = try Self.paragraph(150, in: first.plain)
    coordinator.show(first, from: place)

    var arrived: [String: NSImage] = [:]
    for number in 1...5 {
      arrived["images/\(number).png"] = picture
      coordinator.show(ReadingText(markdown: markdown, images: arrived), from: place)
    }
    try await Task.sleep(for: .milliseconds(200))

    #expect(coordinator.topQuote()?.text.hasPrefix("第 150 段") == true)
    #expect(heard.moves.isEmpty)
  }

  @Test func aParagraphMostlyScrolledPastIsNotWhereTheReaderIs() throws {
    let (coordinator, scrollView, window) = Self.reader(heard: Heard())
    defer { window.orderOut(nil) }
    let text = ReadingText(markdown: Self.long)
    coordinator.show(text, from: try Self.paragraph(150, in: text.plain))
    let textView = try #require(scrollView.documentView as? ReaderTextView)
    let range = try #require(text.range(of: try Self.paragraph(151, in: text.plain)))
    let next = try #require(textView.top(of: range.location))
    let top = scrollView.documentVisibleRect.minY

    scrollView.contentView.scroll(to: CGPoint(x: 0, y: top + (next - ReadingStyle.inset.height - top) * 0.8))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    #expect(coordinator.topQuote()?.text.hasPrefix("第 151 段") == true)
  }

  /// On a slow machine the window may lay the reader out only after the text is shown.
  @Test func aReaderThatGetsItsWidthLateOpensInPlaceAndRemembersWhereItIsLeft() async throws {
    let heard = Heard()
    let coordinator = ReaderCoordinator(
      events: ReaderEvents(moved: { heard.moves.append($0) }, reachedEnd: { heard.ends += 1 }),
      settle: .milliseconds(50))
    let scrollView = coordinator.makeScrollView()
    let text = ReadingText(markdown: Self.long)
    let started = ContinuousClock.now
    coordinator.show(text, from: try Self.paragraph(50, in: text.plain))
    for _ in 0..<20 { scrollView.contentView.scroll(to: CGPoint(x: 0, y: 400)) }
    #expect(ContinuousClock.now - started < .seconds(2))
    #expect(heard.ends == 0)

    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 900, height: 700), styleMask: [.titled], backing: .buffered,
      defer: false)
    defer { window.orderOut(nil) }
    window.contentView = scrollView
    window.layoutIfNeeded()
    #expect(coordinator.topQuote()?.text.hasPrefix("第 50 段") == true)

    scrollView.contentView.scroll(to: CGPoint(x: 0, y: scrollView.documentVisibleRect.minY + 400))
    for _ in 0..<100 where heard.moves.isEmpty { try await Task.sleep(for: .milliseconds(50)) }

    #expect(heard.moves.last?.text.hasPrefix("第 5") == true)
    #expect(heard.ends == 0)
  }

  @Test func aReaderSizedBeforeItIsTiledOpensInPlaceAtOnce() throws {
    let coordinator = ReaderCoordinator(events: ReaderEvents(), settle: .milliseconds(50))
    let scrollView = coordinator.makeScrollView()
    scrollView.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
    let textView = try #require(scrollView.documentView as? ReaderTextView)
    let text = ReadingText(markdown: Self.long)

    coordinator.show(text, from: try Self.paragraph(50, in: text.plain))

    #expect(textView.frame.width > 0)
    #expect(coordinator.topQuote()?.text.hasPrefix("第 50 段") == true)
  }

  /// A scroll bar that appears once the text scrolls, as it does on a Mac without a trackpad, narrows the
  /// column right after the person moved.
  @Test func whereTheReaderIsLeftIsRememberedWhenTheColumnNarrowsRightAfter() async throws {
    let heard = Heard()
    let (coordinator, scrollView, window) = Self.reader(heard: heard)
    defer { window.orderOut(nil) }
    let text = ReadingText(markdown: Self.long)
    coordinator.show(text, from: try Self.paragraph(50, in: text.plain))

    scrollView.contentView.scroll(to: CGPoint(x: 0, y: scrollView.documentVisibleRect.minY + 400))
    let left = try #require(coordinator.topQuote())
    window.setContentSize(CGSize(width: 885, height: 700))
    for _ in 0..<100 where heard.moves.isEmpty { try await Task.sleep(for: .milliseconds(50)) }

    #expect(heard.moves.last?.text == left.text)
    #expect(coordinator.topQuote()?.text == left.text)
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
    try await eventually("the reader to open at paragraph 50") {
      coordinator.topQuote()?.text.hasPrefix("第 50 段") == true
    }

    scrollView.contentView.scroll(to: CGPoint(x: 0, y: scrollView.documentVisibleRect.minY + 400))
    for _ in 0..<100 where heard.moves.isEmpty { try await Task.sleep(for: .milliseconds(50)) }

    let quote = try #require(heard.moves.last)
    #expect(quote.text.hasPrefix("第 5"))
    #expect(quote.range(in: text.plain) != nil)
  }
}
