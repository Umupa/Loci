import AppKit
import LociModel
import SwiftUI

/// An item's Markdown in the reader with Loci's panel beside it. It opens where the reader last was,
/// remembers where they go and whether they reached the end, and shows the highlights left on it.
struct ContentReader: View {
  @Environment(\.host) private var host
  @Environment(\.openPage) private var openPage
  @Environment(\.standIns) private var standIns
  @Environment(\.changesAllowed) private var changesAllowed
  let item: EntityID
  /// Set over the text, unless the text starts with a title of its own.
  let title: String?
  let markdown: String
  /// Under an item's title: who wrote it, where, when, and a link to the original.
  let byline: NSAttributedString?
  /// Pictures the Markdown names, by the address it names them with.
  let images: [String: NSImage]
  let serif: Bool
  let pane: PaneWidth
  /// The article's translation, when it is in another language than the reader's.
  let language: ArticleLanguage?
  let openingQuote: TextQuote?
  @AppStorage(SubtitleMode.key) private var mode = SubtitleMode.both
  @State private var text: ReadingText?
  @State private var start: TextQuote?
  @State private var notes: Feed<[Note]>?
  @State private var reveal: Reveal?
  @State private var tab = PanelTab.conversation
  @State private var chosen: ChosenNote?
  @State private var panelShown = true
  @State private var available = CGFloat.infinity
  @AppStorage private var panelWidth: Double
  @AppStorage(ReadingWidth.key) private var readingWidth = ReadingWidth.comfortable
  @State private var draft: PassageDraft?
  @State private var passageBar = PassagePopover()
  @State private var marks: [ReaderMark] = []
  @State private var placedNotes: [PlacedNote] = []

  init(
    item: EntityID, title: String?, markdown: String, byline: NSAttributedString? = nil,
    images: [String: NSImage] = [:], serif: Bool = false, pane: PaneWidth = .panel, language: ArticleLanguage? = nil,
    openingQuote: TextQuote? = nil
  ) {
    self.language = language
    self.openingQuote = openingQuote
    self.byline = byline
    self.images = images
    self.serif = serif
    self.pane = pane
    _panelWidth = AppStorage(wrappedValue: Double(pane.ideal), pane.key)
    self.item = item
    self.title = title
    self.markdown = Self.titled(markdown, title)
  }

  private var content: ContentRef { .item(item) }

  var body: some View {
    HStack(spacing: 0) {
      reader
      if panelShown {
        ReaderPanel(
          item: item, notes: placedNotes, tab: $tab, draft: $draft, chosen: chosen, reveal: show,
          revealPassage: show, ask: { placed in ask(placed.note.locator, excerpt: placed.note.excerpt) },
          collapse: { withAnimation(Motion.fold) { panelShown = false } }
        )
        .frame(width: pane.fitting(panelWidth, in: available))
        .overlay(alignment: .leading) {
          PaneResizer(pane: pane, width: $panelWidth, maximum: pane.fitting(.infinity, in: available))
        }
        .transition(.move(edge: .trailing))
      }
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      available = $0
    }
    .overlay(alignment: .topTrailing) {
      if !panelShown {
        PanelButton(title: .loci("panel.expand")) { withAnimation(Motion.fold) { panelShown = true } }
          .glassEffect(.regular, in: .capsule)
          .padding(Spacing.s)
      }
    }
    .task(id: content) {
      if standIns?.moment?.panel == .highlights { tab = .highlights }
      let saved = (try? await host.run(ReadReadingState(content: content)))?.position?.quote
      let loaded = setText()
      if text == nil, let openingQuote, let range = loaded.range(of: openingQuote) {
        start = openingQuote
        show(range)
      } else {
        start = saved
      }
      text = loaded
      remark()
    }
    .onChange(of: markdown) {
      guard text != nil else { return }
      text = setText()
      remark()
    }
    .onChange(of: images.keys.sorted()) {
      guard text != nil else { return }
      text = setText()
      remark()
    }
    .onChange(of: shownTranslation) {
      guard text != nil else { return }
      text = setText()
      remark()
    }
    .onChange(of: notes) { remark() }
    .subscribing(NotesOn(content: content), into: $notes)
  }

  @ViewBuilder private var reader: some View {
    if let text {
      Reader(
        text: text, start: start, width: readingWidth, marks: marks, reveal: reveal, selected: standIns?.selection,
        events: events, passageBar: passageBar
      )
      .onDisappear { passageBar.close() }
      .overlay(alignment: .topTrailing) {
        if let language {
          TranslateButton(language: language, mode: $mode) {
            Task { _ = try? await host.run(TranslateArticle(item: item)) }
          }
          .padding(.top, Spacing.xs)
          .padding(.trailing, panelShown ? Spacing.s : Spacing.s * 2 + Size.iconButton)
        }
      }
    } else {
      Palette.canvas
    }
  }

  private var shownTranslation: ShownTranslation? {
    language?.shown(mode)
  }

  private func setText() -> ReadingText {
    ReadingText(markdown: markdown, byline: byline, images: images, serif: serif, translation: shownTranslation)
  }

  private static func titled(_ markdown: String, _ title: String?) -> String {
    guard let title, !markdown.hasPrefix("# ") else { return markdown }
    return "# \(title)\n\n" + markdown
  }

  /// Works out again where highlights sit and what to mark, after the text or anything marked on it changed.
  private func remark() {
    guard let text else { return }
    placedNotes = PlacedNote.place(notes?.value ?? [], in: text)
    marks = PlacedNote.marks(placedNotes)
  }

  private func show(_ range: NSRange) {
    reveal = Reveal(range: range, serial: (reveal?.serial ?? 0) + 1)
  }

  private func show(_ locator: Locator) {
    guard let quote = locator.quote, let range = text?.range(of: quote) else { return }
    show(range)
  }

  private var events: ReaderEvents {
    ReaderEvents(
      moved: { quote in
        Task { _ = try? await host.run(SaveReadingPosition(content: content, position: Locator(quote, in: content))) }
      },
      reachedEnd: {
        Task { _ = try? await host.run(MarkRead(content: content)) }
      },
      openLink: { url in
        if let locator = Locator(url.absoluteString) {
          openPage.follow(locator, in: .item(item), reveal: show)
        } else if url.isWebLink {
          NSWorkspace.shared.open(url)
        }
      },
      passage: passageActions,
      noteClicked: { note in
        withAnimation(Motion.fold) { panelShown = true }
        tab = .highlights
        chosen = ChosenNote(note: note, serial: (chosen?.serial ?? 0) + 1)
        if let range = placedNotes.first(where: { $0.id == note })?.range { show(range) }
      })
  }

  /// Highlighting with an optional thought, and asking Loci about it.
  private var passageActions: PassageActions {
    PassageActions(
      highlight: { range in
        guard let passage = passage(range) else { return nil }
        return try? await host.run(AddNote(locator: passage.locator, excerpt: passage.excerpt)).id
      },
      think: { note, thought in
        Task { _ = try? await host.run(SetNoteThought(content: content, note: note, thought: thought)) }
      },
      ask: { range in
        guard let passage = passage(range) else { return }
        ask(passage.locator, excerpt: passage.excerpt)
      }, changes: changesAllowed)
  }

  /// Puts the passage above Loci's composer and turns the panel to the conversation.
  private func ask(_ locator: Locator, excerpt: String?) {
    draft = PassageDraft(content: content, locator: locator, excerpt: excerpt ?? locator.quote?.text ?? "")
    tab = .conversation
    withAnimation(Motion.fold) { panelShown = true }
  }

  private func passage(_ range: NSRange) -> (locator: Locator, excerpt: String)? {
    guard let passage = text?.quote(range) else { return nil }
    return (Locator(passage.quote, in: content), passage.excerpt)
  }
}

extension Page {
  init(_ content: ContentRef) {
    switch content {
    case .item(let item): self = .item(item)
    }
  }
}

/// Opens a page on top of the current place, as following a link does.
struct OpenPage {
  let action: (Page) -> Void

  func callAsFunction(_ page: Page) {
    action(page)
  }

  @MainActor func follow(_ locator: Locator, in conversation: ConversationRef, reveal: @MainActor (Locator) -> Void) {
    let page = Page.passage(locator)
    if conversation == .item(page.itemID) {
      reveal(locator)
    } else {
      action(page)
    }
  }

  @MainActor func follow(_ url: URL, in conversation: ConversationRef, reveal: @MainActor (Locator) -> Void)
    -> OpenURLAction.Result
  {
    guard url.scheme?.lowercased() == "loci" else { return .systemAction }
    guard let locator = Locator(url.absoluteString) else { return .discarded }
    follow(locator, in: conversation, reveal: reveal)
    return .handled
  }
}

/// Goes to a place in the sidebar, as a fix for stopped work does.
struct OpenPlace {
  let action: (Place) -> Void

  func callAsFunction(_ place: Place) {
    action(place)
  }
}

extension EnvironmentValues {
  @Entry var openPage = OpenPage { _ in }
  @Entry var openPlace = OpenPlace { _ in }
}
