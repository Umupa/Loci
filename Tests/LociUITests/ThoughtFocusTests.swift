import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// HL-S3, HL-S5: right after highlighting, the thought can be typed at once.
@MainActor
@Suite(.serialized, .onStage)
struct ThoughtFocusTests {
  static func window(_ view: some View) throws -> NSWindow {
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 420, height: 320), styleMask: [.titled], backing: .buffered,
      defer: false)
    window.contentView = NSHostingView(
      rootView: view.environment(\.locale, Locale(identifier: "zh-Hans")).lociHost(
        FakeHost(try Sample(problems: false))))
    window.makeKeyAndOrderFront(nil)
    return window
  }

  static func typing(in window: NSWindow) -> Bool {
    window.firstResponder is NSTextView
  }

  static func card(writing: Bool) throws -> some View {
    let note = try Note(
      id: EntityID(), locator: .item(EntityID(), .quote(try TextQuote("\u{FFFC}"))), pictures: ["images/a.png"],
      savedAt: Timestamp(millisecondsSince1970: 0))
    return NoteCard(
      content: .item(EntityID()), placed: PlacedNote(note: note, range: NSRange(location: 0, length: 1)),
      selected: true, writing: writing, flash: nil, ask: nil, select: {}
    )
    .padding()
  }

  @Test func aPictureJustHighlightedOpensItsCardReadyToType() async throws {
    let window = try Self.window(try Self.card(writing: true))
    defer { window.orderOut(nil) }

    try await eventually("the thought field to take typing") { Self.typing(in: window) }
  }

  @Test func aCardChosenByClickingWaitsForAClickInItsField() async throws {
    let window = try Self.window(try Self.card(writing: false))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(300))

    #expect(!Self.typing(in: window))
  }

  @Test func aPassageJustHighlightedTurnsTheBarIntoAFieldReadyToType() async throws {
    let id = EntityID()
    let actions = PassageActions(highlight: { _ in id }, note: .ignored)
    let window = try Self.window(
      PassageBar(actions: actions, mode: .selection(NSRange(location: 0, length: 3)), typing: {}, done: {}))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(300))
    let bar = try #require(window.contentView).fittingSize
    let size = try #require(window.contentView).bounds.size
    #expect(!Self.typing(in: window))

    Self.click(
      window, at: CGPoint(x: (size.width - bar.width) / 2 + Spacing.xxs + Size.iconButton / 2, y: size.height / 2))

    try await eventually("the thought field to take typing") { Self.typing(in: window) }
  }

  /// A click as the mouse makes it, at a point in the window's content.
  static func click(_ window: NSWindow, at point: CGPoint) {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      if let event = NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
      {
        window.sendEvent(event)
      }
    }
  }
}
