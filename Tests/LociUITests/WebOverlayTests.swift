import AppKit
import LociModel
import SwiftUI
import Testing
import WebKit

@testable import LociUI

/// H-S4: a web page opened over the window closes with a click anywhere outside it, and the conversation under
/// it is where it was. The click goes through the window as a real mouse press.
@MainActor
@Suite(.serialized, .onStage)
struct WebOverlayTests {
  enum Side: CaseIterable { case left, right, above, below }

  @Test func aFloatingPageFitsBothWideAndCompactWindows() {
    #expect(WebOverlaySizing(room: CGSize(width: 1200, height: 800)).ideal == CGSize(width: 1072, height: 720))
    let compact = WebOverlaySizing(room: CGSize(width: 720, height: 460))
    #expect(compact.ideal == CGSize(width: 688, height: 428))
    #expect(compact.fitting(CGSize(width: 1112, height: 756)) == compact.ideal)
    #expect(compact.fitting(CGSize(width: 200, height: 180)) == CGSize(width: 520, height: 360))
  }

  @Test func draggingResizesTheSamePageAndReopeningUsesThatSizeUntilReset() async throws {
    let browser = BrowserSession()
    let defaults = LibrarySnapshots.defaults(panel: true)
    let blank = try #require(URL(string: "about:blank"))
    let window = try Self.window(browser, standIns: StandIns(overlayPage: blank), defaults: defaults)
    defer { window.orderOut(nil) }
    try await eventually("the web view to be sized") {
      browser.peeks.first?.view?.frame.width == 1072
    }
    let page = try #require(browser.peeks.first?.view)
    let original = page.frame.size
    let corner = Self.resizePoint(page)
    let moved = CGPoint(x: corner.x + 20, y: corner.y - 18)
    Self.mouse(.leftMouseDown, in: window, at: corner)
    Self.mouse(.leftMouseDragged, in: window, at: moved)
    let expanded = CGSize(width: original.width + 40, height: original.height + 36)
    try await eventually("the page to grow in both directions") { page.frame.size == expanded }
    Self.mouse(.leftMouseUp, in: window, at: moved)
    #expect(browser.peeks.first?.view === page)

    let otherBrowser = BrowserSession()
    let reopened = try Self.window(otherBrowser, standIns: StandIns(overlayPage: blank), defaults: defaults)
    defer { reopened.orderOut(nil) }
    try await eventually("the reopened page to use the remembered size") {
      otherBrowser.peeks.first?.view?.frame.size == expanded
    }
    let otherPage = try #require(otherBrowser.peeks.first?.view)
    Self.click(reopened, at: Self.resizePoint(otherPage), count: 2)
    try await eventually("double-clicking to restore the default size") { otherPage.frame.size == original }
  }

  @Test(arguments: Side.allCases)
  func aClickBesideThePageClosesItAndLeavesTheConversationWhereItWas(side: Side) async throws {
    let browser = BrowserSession()
    let window = try Self.window(
      browser, standIns: StandIns(webPage: NSImage(size: CGSize(width: 10, height: 10)), overlayPage: Self.page),
      defaults: LibrarySnapshots.defaults(panel: true))
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

  /// H-S7: over a page the library keeps, the filled library button closes the page and opens the item.
  @Test func theFilledLibraryButtonOpensTheKeptPageInTheLibrary() async throws {
    let browser = BrowserSession()
    let size = CGSize(width: 1200, height: 800)
    let library = try SampleLibrary()
    let kept = library.article.source
    let shown = Shown()
    let view = MachineWindow(
      memory: WindowMemory(recall: { WindowState() }, remember: { shown.window = $0 }), browser: browser
    )
    .lociHost(FakeHost(try Sample(problems: false), library: library))
    .environment(
      \.standIns,
      StandIns(
        webPage: NSImage(size: CGSize(width: 10, height: 10)), overlayPage: kept,
        overlayFacts: PageFacts(hasArticle: true))
    )
    .defaultAppStorage(LibrarySnapshots.defaults(panel: true))
    .frame(width: size.width, height: size.height)
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: view)
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    try await eventually("the page to open over the conversation") { !browser.peeks.isEmpty }
    try await Task.sleep(for: .seconds(1))

    let side = WebOverlaySizing(room: size).ideal
    let card = CGRect(
      x: (size.width - side.width) / 2, y: (size.height - side.height) / 2, width: side.width, height: side.height)
    let button = CGPoint(
      x: card.maxX - 10 - 2 * Size.iconButton - 4 - Size.iconButton / 2,
      y: size.height - card.minY - WebOverlay.barHeight / 2)
    Self.click(window, at: button)

    try await eventually("the page to close for the item") { browser.peeks.isEmpty }
    try await eventually("the item to open") { shown.window?.pages.last?.itemID == library.article.id }
  }

  /// H-S4: "open in browser" takes the page from over the window into the browser.
  @Test func openInBrowserShowsTheBrowser() async throws {
    let browser = BrowserSession()
    let size = CGSize(width: 1200, height: 800)
    let shown = Shown()
    let view = MachineWindow(
      memory: WindowMemory(recall: { WindowState() }, remember: { shown.window = $0 }), browser: browser
    )
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
    try await eventually("the page to open over the conversation") { !browser.peeks.isEmpty }
    try await Task.sleep(for: .seconds(1))

    let side = WebOverlaySizing(room: size).ideal
    let card = CGRect(
      x: (size.width - side.width) / 2, y: (size.height - side.height) / 2, width: side.width, height: side.height)
    Self.click(
      window,
      at: CGPoint(
        x: card.maxX - 10 - Size.iconButton - 2 - Size.iconButton / 2,
        y: size.height - card.minY - WebOverlay.barHeight / 2))

    try await eventually("the browser to show") { shown.window?.place == .browser }
    #expect(browser.peeks.isEmpty)
  }

  /// The window as it last remembered itself.
  @MainActor final class Shown {
    var window: WindowState?
  }

  private static let page = URL(string: "https://blog.cloudflare.com/how-we-built-pingora")

  private static func window(_ browser: BrowserSession, standIns: StandIns, defaults: UserDefaults) throws -> NSWindow {
    let size = CGSize(width: 1200, height: 800)
    let view = MachineWindow(memory: WindowMemory(recall: { WindowState() }, remember: { _ in }), browser: browser)
      .lociHost(FakeHost(try Sample(problems: false), library: try SampleLibrary()))
      .environment(\.standIns, standIns)
      .defaultAppStorage(defaults)
      .frame(width: size.width, height: size.height)
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: view)
    window.orderBack(nil)
    return window
  }

  private static func resizePoint(_ page: WKWebView) -> CGPoint {
    let frame = page.convert(page.bounds, to: nil)
    return CGPoint(x: frame.maxX - 16, y: frame.minY + 16)
  }

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

  private static func click(_ window: NSWindow, at point: CGPoint, count: Int = 1) {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      mouse(type, in: window, at: point, count: count)
    }
  }

  private static func mouse(_ type: NSEvent.EventType, in window: NSWindow, at point: CGPoint, count: Int = 1) {
    let event = NSEvent.mouseEvent(
      with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1)
    if let event { window.sendEvent(event) }
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
