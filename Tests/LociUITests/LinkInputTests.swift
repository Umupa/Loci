import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import LociUI

/// L-S1: a link reaches the library by ⌘V wherever the keyboard is, or by dragging it in from another app.
@MainActor
struct LinkInputTests {
  static let link = URL(string: "https://blog.cloudflare.com/new-standards/")!

  static func key(_ characters: String, _ modifiers: NSEvent.ModifierFlags) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
      characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 9)
  }

  @Test func commandVIsTakenWhenTheSidebarOrNothingHasTheKeyboard() throws {
    let paste = try #require(Self.key("v", .command))
    #expect(LinkPasteMonitor.takes(paste, typingInto: NSTableView()))
    #expect(LinkPasteMonitor.takes(paste, typingInto: nil))
    #expect(LinkPasteMonitor.takes(paste, typingInto: NSWindow()))
  }

  @Test func aFieldBeingTypedIntoKeepsCommandV() throws {
    let paste = try #require(Self.key("v", .command))
    #expect(!LinkPasteMonitor.takes(paste, typingInto: NSTextView()))
  }

  @Test func onlyCommandVIsTaken() throws {
    #expect(!LinkPasteMonitor.takes(try #require(Self.key("v", [])), typingInto: nil))
    #expect(!LinkPasteMonitor.takes(try #require(Self.key("v", [.command, .shift])), typingInto: nil))
    #expect(!LinkPasteMonitor.takes(try #require(Self.key("c", .command)), typingInto: nil))
  }

  @Test func aLinkIsReadFromThePasteboardAsALinkOrAsText() {
    let board = NSPasteboard(name: NSPasteboard.Name("loci-test-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }

    board.clearContents()
    board.writeObjects([Self.link as NSURL])
    #expect(PastedLink.on(board) == Self.link)

    board.clearContents()
    board.setString("  \(Self.link.absoluteString)\n", forType: .string)
    #expect(PastedLink.on(board) == Self.link)

    board.clearContents()
    board.setString("explain the scheduler", forType: .string)
    #expect(PastedLink.on(board) == nil)
  }

  @Test func aDraggedLinkIsAdded() async {
    let dropped = await Dropped.collect(Dropped.reading([NSItemProvider(object: Self.link as NSURL)]))
    #expect(dropped == [.link(Self.link)])
  }

  @Test func draggedTextHoldingOneLinkIsAdded() async {
    let words = "Read this: \(Self.link.absoluteString) — it is good"
    #expect(
      await Dropped.collect(Dropped.reading([NSItemProvider(object: Self.link.absoluteString as NSString)])) == [
        .link(Self.link)
      ])
    #expect(await Dropped.collect(Dropped.reading([NSItemProvider(object: words as NSString)])) == [.link(Self.link)])
    #expect(await Dropped.collect(Dropped.reading([NSItemProvider(object: "just words" as NSString)])).isEmpty)
  }

  @Test func aDraggedTextFileIsAdded() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "loci-drop-\(UUID().uuidString).md")
    try Data("# Notes\n".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }

    let dropped = await Dropped.collect(Dropped.reading([try #require(NSItemProvider(contentsOf: file))]))

    #expect(dropped == [.textFile(try TextFile(reading: file))])
    guard case .textFile(let text)? = dropped.first else { return }
    #expect(text.text == "# Notes\n")
  }

  @Test func aDraggedLinkThatIsNotOnTheWebIsLeftOut() async {
    let mail = URL(string: "mailto:someone@example.com")!
    #expect(await Dropped.collect(Dropped.reading([NSItemProvider(object: mail as NSURL)])).isEmpty)
  }
}
