import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// H-S4: a web page opened over the window closes with a click anywhere outside it, and the conversation under
/// it is where it was. The click goes through the window as a real mouse press.
@MainActor
@Suite(.onStage)
struct WebOverlayTests {
  enum Side: CaseIterable { case left, right, above, below }

  @Test(arguments: Side.allCases)
  func aClickBesideThePageClosesItAndLeavesTheConversationWhereItWas(side: Side) async throws {
    let browser = BrowserSession()
    let size = CGSize(width: 1200, height: 800)
    let view = MachineWindow(memory: WindowMemory(recall: { WindowState() }, remember: { _ in }), browser: browser)
      .lociHost(FakeHost(try Sample(problems: false), library: try SampleLibrary()))
      .environment(\.standIns, StandIns(webPage: NSImage(size: CGSize(width: 10, height: 10)), overlayPage: Self.page))
      .defaultAppStorage(LibrarySnapshots.defaults(panel: true))
      .frame(width: size.width, height: size.height)
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: view)
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    try await eventually("the page to open over the conversation") {
      !browser.peeks.isEmpty && Self.conversation(in: window) != nil
    }
    let scroll = try #require(Self.conversation(in: window))
    try await eventually("the conversation to settle") { scroll.contentView.bounds.minY > 0 }
    let scrolled = scroll.contentView.bounds.minY

    Self.click(window, at: try Self.point(side, in: window))

    try await eventually("the page to close") { browser.peeks.isEmpty }
    #expect(scroll.contentView.bounds.minY == scrolled)
  }

  private static let page = URL(string: "https://blog.cloudflare.com/how-we-built-pingora")

  /// A point between the edge of the window and the page over it, in window coordinates.
  private static func point(_ side: Side, in window: NSWindow) throws -> CGPoint {
    let room = try #require(window.contentView).bounds
    switch side {
    case .left: return CGPoint(x: room.minX + 12, y: room.midY)
    case .right: return CGPoint(x: room.maxX - 24, y: room.midY)
    case .above: return CGPoint(x: room.midX, y: room.maxY - 12)
    case .below: return CGPoint(x: room.midX, y: room.minY + 12)
    }
  }

  private static func click(_ window: NSWindow, at point: CGPoint) {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      let event = NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
      if let event { window.sendEvent(event) }
    }
  }

  /// The scroll view of the conversation: the tallest one in the window.
  private static func conversation(in window: NSWindow) -> NSScrollView? {
    guard let root = window.contentView else { return nil }
    return scrollViews(in: root).max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
  }

  private static func scrollViews(in view: NSView) -> [NSScrollView] {
    (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap(scrollViews(in:))
  }
}
