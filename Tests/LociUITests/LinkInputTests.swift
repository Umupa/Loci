import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import LociUI

/// L-S1: a link reaches the library by ⌘V wherever the keyboard is, or by dragging it in from another app.
@MainActor
@Suite(.onStage)
struct LinkInputTests {
  static let link = URL(string: "https://blog.cloudflare.com/new-standards/")!

  static func key(_ characters: String, _ modifiers: NSEvent.ModifierFlags) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
      characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 9)
  }

  @Test func commandVIsTakenWhenTheSidebarOrNothingHasTheKeyboard() throws {
    let paste = try #require(Self.key("v", .command))
    #expect(LinkPasteKey.isPaste(paste))
    #expect(!KeyMonitor.isTyping(into: NSTableView()))
    #expect(!KeyMonitor.isTyping(into: nil))
    #expect(!KeyMonitor.isTyping(into: NSWindow()))
  }

  @Test func aFieldBeingTypedIntoKeepsItsKeys() {
    #expect(KeyMonitor.isTyping(into: NSTextView()))
  }

  @Test func onlyCommandVIsTaken() throws {
    #expect(!LinkPasteKey.isPaste(try #require(Self.key("v", []))))
    #expect(!LinkPasteKey.isPaste(try #require(Self.key("v", [.command, .shift]))))
    #expect(!LinkPasteKey.isPaste(try #require(Self.key("c", .command))))
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

  /// A-S3: a video or audio file is added as itself, not read as text.
  @Test func aDraggedVideoOrAudioFileIsAddedAsMedia() async throws {
    for name in ["talk.mp4", "episode.m4a"] {
      let file = FileManager.default.temporaryDirectory.appending(path: "loci-drop-\(UUID().uuidString)-\(name)")
      try Data("media".utf8).write(to: file)
      defer { try? FileManager.default.removeItem(at: file) }

      let dropped = await Dropped.collect(Dropped.reading([try #require(NSItemProvider(contentsOf: file))]))

      #expect(dropped == [.mediaFile(file)])
    }
  }

  /// A-S2: the field takes the link pasted alone or shared among words, and nothing else.
  @Test func theLinkFieldFindsTheLinkInWhatIsPasted() {
    let shared = "7.92 复制打开抖音，看看【猫和狗的作品】 https://v.douyin.com/iRNBho6u/ 你好"
    #expect(LinkField.link(in: "  \(Self.link.absoluteString)\n") == Self.link)
    #expect(LinkField.link(in: shared) == URL(string: "https://v.douyin.com/iRNBho6u/"))
    #expect(LinkField.link(in: "explain the scheduler") == nil)
    #expect(LinkField.link(in: "") == nil)
  }

  /// A-S1: each page says what it takes.
  @Test func theLinkFieldSaysWhatEachPageTakes() {
    #expect(LinkField.prompt(for: nil).key == "link.prompt")
    #expect(LinkField.prompt(for: .video).key == "link.promptVideo")
    #expect(LinkField.prompt(for: .audio).key == "link.promptAudio")
    #expect(LinkField.prompt(for: .paper).key == "link.promptPaper")
  }

  @Test func aDraggedLinkThatIsNotOnTheWebIsLeftOut() async {
    let mail = URL(string: "mailto:someone@example.com")!
    #expect(await Dropped.collect(Dropped.reading([NSItemProvider(object: mail as NSURL)])).isEmpty)
  }
}
