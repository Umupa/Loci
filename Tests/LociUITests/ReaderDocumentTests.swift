import AppKit
import LociModel
import SwiftUI
import Testing
import Vision

@testable import LociUI

@MainActor
@Suite(.onStage(alone: true))
struct ReaderDocumentTests {
  private static let size = CGSize(width: 1560, height: 820)

  @Test func aDocumentInTheReadersConversationOpensCenteredOverTheWholePage() async throws {
    let (window, host) = try show()
    defer { window.orderOut(nil) }
    var title: CGPoint?
    try await eventually("the document card to appear beside the text", within: .seconds(30)) {
      title = try? Self.place(of: "Isolation notes", in: host)
      return title != nil
    }
    try Self.click(at: try #require(title), in: window)
    try await eventually("the document to open centered over the text and the panel", within: .seconds(10)) {
      Self.scrollViews(in: host).contains { scroll in
        let frame = scroll.convert(scroll.bounds, to: host)
        let sidebarWidth = PaneWidth.sidebar.ideal + Spacing.xs * 2
        return frame.width >= 700 && abs(frame.midX - (host.bounds.width + sidebarWidth) / 2) < 2
      }
    }
  }

  private func show() throws -> (NSWindow, NSView) {
    let sample = try Sample(problems: false)
    let ref = ConversationRef.item(sample.borg.id)
    let at = Date(timeIntervalSince1970: 1_763_400_000)
    var entropy = Sample.Seeded()
    let entries = [
      Message.Body.prompt(Prompt(text: "What does the jailer isolate?", purpose: .chat)),
      .reply("Three things.\n\n````loci-doc\n# Isolation notes\n\n" + Self.body + "\n````"),
    ].enumerated().map { index, body in
      let date = at + Double(index)
      return Conversation.Entry.message(
        Message(
          id: EntityID(at: date, entropy: &entropy),
          at: Timestamp(millisecondsSince1970: Int64(date.timeIntervalSince1970 * 1000)), body: body))
    }
    let fake = FakeHost(sample, chat: Conversation(ref: ref, entries: entries, turn: nil))
    let defaults = PanelSnapshots.defaults(columnShown: true, sidebarShown: true, layout: nil)
    defaults.set(true, forKey: PanelMemory.key)
    let view = MachineWindow(
      memory: WindowMemory(
        recall: { WindowState(place: .library(nil), pages: [.item(sample.borg.id)]) }, remember: { _ in })
    )
    .lociHost(fake)
    .defaultAppStorage(defaults)
    let host = NSHostingView(
      rootView: view.environment(\.locale, Locale(identifier: "en")).environment(\.suppressMotion, true)
        .frame(width: Self.size.width, height: Self.size.height))
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: Self.size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    window.orderBack(nil)
    return (window, host)
  }

  private static let body = (1...6).map { "Paragraph \($0) of what the jailer keeps apart." }.joined(separator: "\n\n")

  private static func place(of text: String, in host: NSView) throws -> CGPoint? {
    host.layoutSubtreeIfNeeded()
    let image = try #require(Snapshot.bitmap(of: host).cgImage)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: image).perform([request])
    guard let found = (request.results ?? []).first(where: { $0.topCandidates(1).first?.string == text }) else {
      return nil
    }
    let box = found.boundingBox
    return CGPoint(x: box.midX * host.bounds.width, y: (1 - box.midY) * host.bounds.height)
  }

  private static func scrollViews(in view: NSView) -> [NSScrollView] {
    if let scroll = view as? NSScrollView { return [scroll] }
    return view.subviews.flatMap(scrollViews(in:))
  }

  private static func click(at point: CGPoint, in window: NSWindow) throws {
    let host = try #require(window.contentView)
    let location = host.convert(
      NSPoint(x: point.x, y: host.isFlipped ? point.y : host.bounds.height - point.y), to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = try #require(
        NSEvent.mouseEvent(
          with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
      window.sendEvent(event)
    }
  }
}
