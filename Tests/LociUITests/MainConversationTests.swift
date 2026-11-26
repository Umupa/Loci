import AppKit
import LociModel
import SwiftUI
import Testing
import Vision

@testable import LociUI

@MainActor
@Suite(.onStage(alone: true))
struct MainConversationTests {
  fileprivate static let size = CGSize(width: 1560, height: 820)
  fileprivate static let documentReplies = ["A short conclusion.", ChatCardSnapshots.document]

  @Test func returningFromTheLibraryKeepsTheMessagesYouWereReading() async throws {
    let (window, host) = try Self.show(Self.history)
    defer { window.orderOut(nil) }
    let initial = try await Self.atEnd(in: host)
    try await Self.scrollUp(initial)
    let before = try Self.visibleQuestions(in: host)
    #expect(!before.isEmpty)
    try Self.click(x: 55, y: 170, in: window)
    try await eventually("the library to replace the conversation", within: .seconds(5)) {
      Self.scrollView(in: host) !== initial
    }
    try Self.click(x: 70, y: 85, in: window)
    try await eventually("the conversation to reload", within: .seconds(5)) {
      guard let scroll = Self.scrollView(in: host) else { return false }
      return (scroll.documentView?.bounds.height ?? 0) > 10_000 && scroll !== initial
    }
    try await Task.sleep(for: .milliseconds(450))
    let after = try Self.visibleQuestions(in: host)
    #expect(!before.isDisjoint(with: after))
  }

  @Test func returningToTheLatestAfterReadingFarBackShowsMessagesAtTheEnd() async throws {
    let (window, host) = try Self.show(Self.history)
    defer { window.orderOut(nil) }
    let scroll = try await Self.atEnd(in: host)
    try await Self.scrollUp(scroll)
    let frame = scroll.convert(scroll.bounds, to: nil)
    try Self.click(x: frame.midX, y: host.bounds.height - frame.minY - 85, in: window)
    try await eventually("the scroll view to reach the bottom", within: .seconds(5)) {
      Self.distanceFromEnd(scroll) < 2
    }
    try await Task.sleep(for: .milliseconds(600))
    #expect(Self.distanceFromEnd(scroll) < 2)
    #expect(try Self.visibleQuestions(in: host).contains("Question 180"))
  }

  @Test func openingADocumentCentersItAcrossTheConversationAndItsPanels() async throws {
    let (window, host) = try Self.show(Self.documentReplies, panels: SamplePanels.column())
    defer { window.orderOut(nil) }
    try await eventually("the document card and panels to appear", within: .seconds(5)) {
      Self.documentCardIsReady(in: host)
    }
    try Self.openDocument(in: window, host: host)
    try await eventually("the centered document to cover the panels", within: .seconds(5)) {
      Self.documentIsCentered(in: host)
    }
    let document = try #require(Self.scrollViews(in: host).first { $0.bounds.width >= 700 })
    try Self.click(x: document.convert(document.bounds, to: nil).minX + 31, y: 56, in: window)
    try await eventually("the document to return to its card", within: .seconds(5)) {
      Self.scrollViews(in: host).count == 2
    }
  }

  private static let history = (1...180).map { message in
    (1...(message % 4 + 1)).map { section in
      "Message \(message), part \(section). " + String(repeating: "A line from the conversation. ", count: message % 12)
    }.joined(separator: "\n\n")
  }

  private static func show(
    _ replies: [String], panels: PanelColumn? = nil, columnShown: Bool = true
  ) throws -> (NSWindow, NSView) {
    let host = NSHostingView(
      rootView: try scene(replies, panels: panels, columnShown: columnShown)
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.suppressMotion, replies.count < 3)
        .frame(width: size.width, height: size.height))
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    window.orderBack(nil)
    return (window, host)
  }

  fileprivate static func scene(
    _ replies: [String], panels: PanelColumn?, columnShown: Bool = true
  ) throws -> some View {
    var entropy = Sample.Seeded()
    func message(_ second: Int, _ body: Message.Body) -> Conversation.Entry {
      let at = Date(timeIntervalSince1970: 1_763_400_000 + Double(second))
      return Conversation.Entry.message(
        Message(
          id: EntityID(at: at, entropy: &entropy),
          at: Timestamp(millisecondsSince1970: Int64(at.timeIntervalSince1970 * 1000)), body: body))
    }
    let entries = replies.enumerated().flatMap { index, reply in
      [
        message(index * 2, .prompt(Prompt(text: "Question \(index + 1)", purpose: .chat))),
        message(index * 2 + 1, .reply(reply)),
      ]
    }
    let chat = Conversation(ref: .main, entries: entries, turn: nil)
    let fake = FakeHost(try Sample(problems: false), panels: panels ?? PanelColumn(slots: []), chat: chat)
    let defaults = PanelSnapshots.defaults(
      columnShown: columnShown, sidebarShown: true,
      layout: TalkLayout.standard.holding(panels?.slots.map(\.key) ?? []).arranged(.panelsLeft))
    return MachineWindow(memory: WindowMemory(recall: { WindowState() }, remember: { _ in }))
      .lociHost(fake)
      .defaultAppStorage(defaults)
  }

  private static func atEnd(in host: NSView) async throws -> NSScrollView {
    try await eventually("the end of the conversation to appear", within: .seconds(5)) {
      guard let scroll = scrollView(in: host), scroll.documentVisibleRect.minY > 1000 else { return false }
      return abs(distanceFromEnd(scroll)) < 2
    }
    return try #require(scrollView(in: host))
  }

  private static func scrollUp(_ scroll: NSScrollView) async throws {
    let before = scroll.documentVisibleRect.minY
    for phase in [CGScrollPhase.began] + Array(repeating: .changed, count: 14) + [.ended] {
      let event = try #require(
        CGEvent(
          scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: phase == .ended ? 0 : 500, wheel2: 0,
          wheel3: 0))
      event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
      scroll.scrollWheel(with: try #require(NSEvent(cgEvent: event)))
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(scroll.documentVisibleRect.minY < before - 3000)
  }

  private static func distanceFromEnd(_ scroll: NSScrollView) -> CGFloat {
    (scroll.documentView?.bounds.maxY ?? 0) + scroll.contentInsets.bottom - scroll.documentVisibleRect.maxY
  }

  private static func visibleQuestions(in host: NSView) throws -> Set<String> {
    host.layoutSubtreeIfNeeded()
    let image = try #require(Snapshot.bitmap(of: host).cgImage)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    try VNImageRequestHandler(cgImage: image).perform([request])
    return Set(
      (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.filter {
        $0.wholeMatch(of: /Question \d+/) != nil
      })
  }

  private static func scrollViews(in view: NSView) -> [NSScrollView] {
    if let scroll = view as? NSScrollView { return [scroll] }
    return view.subviews.flatMap(scrollViews(in:))
  }

  private static func scrollView(in view: NSView) -> NSScrollView? {
    scrollViews(in: view).first { $0.bounds.width >= 450 }
  }

  fileprivate static func documentCardIsReady(in host: NSView) -> Bool {
    scrollViews(in: host).count == 2 && (scrollView(in: host)?.documentView?.bounds.height ?? 0) > 350
  }

  fileprivate static func openDocument(in window: NSWindow, host: NSView) throws {
    let scroll = try #require(scrollView(in: host))
    let frame = scroll.convert(scroll.bounds, to: nil)
    try click(x: frame.minX + 150, y: 400, in: window)
  }

  fileprivate static func documentIsCentered(in host: NSView) -> Bool {
    scrollViews(in: host).contains { scroll in
      let frame = scroll.convert(scroll.bounds, to: host)
      let sidebarWidth = PaneWidth.sidebar.ideal + Spacing.xs * 2
      return frame.width >= 700 && abs(frame.midX - (host.bounds.width + sidebarWidth) / 2) < 2
    }
  }

  private static func click(x: CGFloat, y: CGFloat, in window: NSWindow) throws {
    let host = try #require(window.contentView)
    let location = host.convert(NSPoint(x: x, y: host.isFlipped ? y : host.bounds.height - y), to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = try #require(
        NSEvent.mouseEvent(
          with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
      window.sendEvent(event)
    }
  }
}

@MainActor
@Suite(.onStage(alone: true))
struct MainConversationSnapshots {
  @Test(arguments: Snapshot.Appearance.allCases)
  func anOpenDocumentIsCenteredInTheMainPanel(appearance: Snapshot.Appearance) async throws {
    let view = try MainConversationTests.scene(MainConversationTests.documentReplies, panels: SamplePanels.column())
    var opened = false
    try await Snapshot.render(
      view, named: "main-conversation-document", size: MainConversationTests.size, appearance: appearance,
      until: { window in
        guard let host = window.contentView else { return false }
        if !opened, MainConversationTests.documentCardIsReady(in: host) {
          try? MainConversationTests.openDocument(in: window, host: host)
          opened = true
        }
        return MainConversationTests.documentIsCentered(in: host)
      }, steady: true)
  }
}
