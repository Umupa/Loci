import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// HL-S1–HL-S7: the highlights panel, the bars over the text and over a picture, and the key points switch.
@MainActor
@Suite(.serialized, .onStage)
struct HighlightSnapshots {
  static let markdown = """
    An always-on agent spends most of its life waiting. The interesting design question is not how it thinks, \
    but how it remembers to wake up.

    ## Timers

    Timers live in their own durable store, usually another database table, separate from the inbox. The inbox \
    should only hold events that are ready to be worked on.

    ![](images/timers.png)

    As a rule of thumb, memory should only hold what the agent cannot look up again.
    """

  static let item = try? Item(id: EntityID(), kind: .article, title: "Building agents that stay on", language: "en")

  /// A diagram on white, as a figure in an article is.
  static let picture = NSImage(size: NSSize(width: 560, height: 250), flipped: true) { frame in
    NSColor.white.setFill()
    frame.fill()
    let ink = NSColor(white: 0.17, alpha: 1)
    let orange = NSColor(red: 0.85, green: 0.47, blue: 0.17, alpha: 1)
    for (rect, color) in [
      (CGRect(x: 20, y: 90, width: 90, height: 50), ink), (CGRect(x: 175, y: 20, width: 210, height: 160), orange),
      (CGRect(x: 445, y: 90, width: 100, height: 50), orange), (CGRect(x: 235, y: 200, width: 95, height: 40), ink),
    ] {
      color.setStroke()
      let box = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
      box.lineWidth = 1.8
      box.stroke()
    }
    ink.setStroke()
    let arrows = NSBezierPath()
    arrows.move(to: CGPoint(x: 110, y: 115))
    arrows.line(to: CGPoint(x: 175, y: 115))
    arrows.move(to: CGPoint(x: 385, y: 115))
    arrows.line(to: CGPoint(x: 445, y: 115))
    arrows.lineWidth = 1.6
    arrows.stroke()
    return true
  }

  static let images = ["images/timers.png": picture]

  static func notes(on item: EntityID, whole: Bool = true) throws -> [Note] {
    let text = ReadingText(markdown: markdown, images: images)
    let saved = Timestamp(millisecondsSince1970: 1_763_337_700_000)
    func note(_ words: String, thought: String? = nil, exchanges: [Note.Exchange] = []) throws -> Note {
      try Note(
        id: EntityID(), locator: .item(item, .quote(try TextQuote(words))), excerpt: words, thought: thought,
        exchanges: exchanges, savedAt: saved)
    }
    let figure = try #require(text.quote((text.plain as NSString).range(of: "\u{FFFC}")))
    let answer = try Note.Exchange(
      question: "为什么不把定时器也放进收件箱？", answer: "收件箱只放现在就能处理的事件；定时器到点才变成事件。", askedAt: saved)
    return [
      try note("The interesting design question is not how it thinks, but how it remembers to wake up."),
      try note("Timers live in their own durable store", thought: "定时器的设计很有意思"),
      try Note(
        id: EntityID(), locator: .item(item, .quote(figure.quote)), pictures: figure.pictures, savedAt: saved),
      try note("memory should only hold what the agent cannot look up again", exchanges: [answer]),
    ]
      + (whole
        ? [
          try Note(
            id: EntityID(), locator: .item(item, .whole), thought: "定时器和收件箱分开，这个拆法可以直接用在跟进上。", savedAt: saved)
        ] : [])
  }

  static func panel(whole: Bool) throws -> some View {
    let item = try #require(Self.item)
    let notes = try Self.notes(on: item.id, whole: whole)
    let text = ReadingText(markdown: markdown, images: images)
    let placed = PlacedNote.place(notes, in: text)
    return ReaderPanel(
      content: .item(item.id), item: item, whole: notes.first(where: \.isWhole), notes: placed, images: images,
      keyPoints: nil, openKeyPoint: { _ in }, tab: .constant(.highlights), draft: .constant(nil),
      chosen: ChosenNote(note: placed[0].id, serial: 1), reveal: { _ in }, revealPassage: { _ in }, ask: { _ in },
      collapse: {}
    )
    .lociHost(FakeHost(try Sample(problems: false)))
  }

  /// HL-S1, HL-S2, HL-S4, HL-S6: the whole card, plain words, a thought, the chosen card with its field, a picture.
  @Test(arguments: Snapshot.Appearance.allCases)
  func highlightsPanel(appearance: Snapshot.Appearance) async throws {
    try await ScreenSnapshots.shoot(
      "highlights-cards", try Self.panel(whole: true), appearance: appearance, size: CGSize(width: 384, height: 900))
  }

  /// HL-S6: the whole card waiting to be written, in English.
  @Test(arguments: Snapshot.Appearance.allCases)
  func emptyWholeCard(appearance: Snapshot.Appearance) async throws {
    try await ScreenSnapshots.shoot(
      "highlights-whole-empty", try Self.panel(whole: false), appearance: appearance, english: true,
      size: CGSize(width: 384, height: 520))
  }

  /// HL-S3, HL-S5: the text with a thought underlined, a highlighted picture framed, and the tools over it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func pictureTools(appearance: Snapshot.Appearance) async throws {
    let item = try #require(Self.item)
    var sample = try Sample(problems: false)
    sample.notes = try Self.notes(on: item.id)
    let reader = ContentReader(
      content: .item(item.id), item: item, title: item.title, markdown: Self.markdown, images: Self.images,
      serif: true, pane: .itemPanel
    )
    .environment(\.standIns, StandIns(moment: MediaMoment(panel: .highlights)))
    .defaultAppStorage(LibrarySnapshots.defaults(panel: true))
    .lociHost(FakeHost(sample))
    let file = try await Snapshot.render(
      reader, named: "highlights-reader", size: ScreenSnapshots.wide, appearance: appearance,
      until: { window in Self.hoverPicture(in: window) }, steady: true)
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  /// Rests the pointer on the picture, once it is laid out; ready once the tools are over it.
  static func hoverPicture(in window: NSWindow) -> Bool {
    guard let view = window.contentView.flatMap(textView(in:)), let storage = view.textStorage else { return false }
    let location = (storage.string as NSString).range(of: "\u{FFFC}").location
    guard location != NSNotFound, let frame = view.pictureFrame(at: location), !view.markedPictures.isEmpty else {
      return false
    }
    view.hover(view.pictureSpot(at: CGPoint(x: frame.midX, y: frame.midY)))
    return view.hoveredPicture != nil
      && view.subviews.contains { String(describing: type(of: $0)).hasPrefix("NSHostingView") }
  }

  static func textView(in view: NSView) -> ReaderTextView? {
    if let found = view as? ReaderTextView { return found }
    return view.subviews.lazy.compactMap(textView(in:)).first
  }

  /// HL-S5: the bar over a new selection, and over a highlight with a thought.
  @Test(arguments: Snapshot.Appearance.allCases)
  func bars(appearance: Snapshot.Appearance) async throws {
    let actions = PassageActions(highlight: { _ in nil }, ask: { _ in }, note: .ignored)
    let bars = VStack(alignment: .leading, spacing: Spacing.l) {
      PassageBar(actions: actions, mode: .selection(NSRange()), typing: {}, done: {})
      PassageBar(actions: actions, mode: .note(EntityID(), thought: "定时器的设计很有意思"), typing: {}, done: {})
      PictureTools(marked: false, changes: true, highlight: {}, ask: {})
      PictureTools(marked: true, changes: true, highlight: {}, ask: {})
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Palette.canvas)
    try await ScreenSnapshots.shoot(
      "highlight-bars", bars, appearance: appearance, size: CGSize(width: 420, height: 300))
  }

  /// HL-S7: the key points switch off and on, beside the translate button.
  @Test(arguments: Snapshot.Appearance.allCases)
  func onlyKeyPoints(appearance: Snapshot.Appearance) async throws {
    let row = HStack(spacing: Spacing.l) {
      ForEach([false, true], id: \.self) { on in
        HStack(spacing: Spacing.xs) {
          OnlyKeyPointsButton(on: .constant(on))
          TranslateButton(
            language: ArticleLanguage(translation: nil, progress: nil), mode: .constant(.both), translate: {})
        }
      }
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    let file = try await Snapshot.render(
      row, named: "only-key-points", size: CGSize(width: 260, height: 100), appearance: appearance)
    #expect(try Data(contentsOf: file).count > 1_000)
  }
}
