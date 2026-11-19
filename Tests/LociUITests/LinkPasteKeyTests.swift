import AppKit
import SwiftUI
import Testing

@testable import LociUI

/// ⌘V sent through the application as a real key press, in a window with a text field and the paste monitor.
/// The test app is never active, so its Edit menu does not paste; what is checked is that the monitor leaves a
/// field being typed into alone, so the field's own paste is the only thing ⌘V does there.
@MainActor
@Suite(.serialized)
struct LinkPasteKeyTests {
  static let link = "https://blog.cloudflare.com/new-standards/"

  final class Counter {
    var pastes = 0
  }

  static func press(focusField: Bool) async throws -> (field: String, pastes: Int) {
    let saved = NSPasteboard.general.string(forType: .string)
    defer {
      NSPasteboard.general.clearContents()
      if let saved { NSPasteboard.general.setString(saved, forType: .string) }
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(link, forType: .string)

    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 400, height: 200), styleMask: [.titled], backing: .buffered,
      defer: false)
    let container = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
    let field = NSTextField(frame: CGRect(x: 20, y: 80, width: 360, height: 24))
    let monitor = KeyMonitor(frame: .zero)
    let counter = Counter()
    monitor.handle = { event in
      guard LinkPasteKey.isPaste(event) else { return false }
      counter.pastes += 1
      return true
    }
    container.addSubview(field)
    container.addSubview(monitor)
    window.contentView = container
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    window.makeFirstResponder(focusField ? field : container)

    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, characters: "v", charactersIgnoringModifiers: "v",
        isARepeat: false, keyCode: 9))
    NSApplication.shared.sendEvent(event)
    try await Task.sleep(for: .milliseconds(200))
    return (field.currentEditor()?.string ?? field.stringValue, counter.pastes)
  }

  @Test func aFieldBeingTypedIntoIsLeftToPasteForItself() async throws {
    let result = try await Self.press(focusField: true)
    #expect(result.pastes == 0)
    #expect(["", Self.link].contains(result.field), "field: \(result.field.debugDescription)")
  }

  @Test func withNoFieldFocusedTheLinkIsAddedOnceAndNothingIsTyped() async throws {
    let result = try await Self.press(focusField: false)
    #expect(result.pastes == 1)
    #expect(result.field.isEmpty)
  }
}
