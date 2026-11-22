import AppKit
import LociModel
import SwiftUI

/// Markdown to read — an item's text or a lesson — with Loci's panel beside it. It opens where the reader last
/// was, remembers where they go and whether they reached the end, and shows the highlights left on it. Once the
/// end has been in view, `ending` rises at the foot of the text.
struct ContentReader<Ending: View>: View {
  @Environment(\.host) private var host
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.openPage) private var openPage
  @Environment(\.standIns) private var standIns
  @Environment(\.changesAllowed) private var changesAllowed
  let content: ContentRef
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
  let placeholder: FetchingItem?
  /// The number of the source a link cites, for text whose links to its sources are citations.
  let cite: ((URL) -> Int?)?
  /// Where a web link opens; the system's browser when `nil`.
  let openWeb: ((URL) -> Void)?
  /// Whether a thin amber line along the top shows how far down the text has been read.
  let showsProgress: Bool
  @State private var progress = 0.0
  let ending: Ending
  @State private var ended = false
  @AppStorage(SubtitleMode.key) private var mode = SubtitleMode.both
  @AppStorage(SubtitleStyle.key) private var style = SubtitleStyle.standard
  @State private var keyPoints: Feed<KeyPointsPage>?
  @State private var onlyKeyPoints = false
  @State private var revealedKey: (number: Int, serial: Int)?
  @State private var text: ReadingText?
  @State private var start: TextQuote?
  @State private var notes: Feed<[Note]>?
  @State private var reveal: Reveal?
  @State private var tab = SideTab.conversation
  @State private var chosen: ChosenNote?
  @AppStorage(PanelMemory.key) private var panelShown = PanelMemory.shownAtFirst
  /// The panel laid over the text, asked for where there is no room for it beside the text.
  @State private var floating = false
  @State private var available = CGFloat.infinity
  @AppStorage private var panelWidth: Double
  @AppStorage(ReadingWidth.key) private var readingWidth = ReadingWidth.comfortable
  @State private var draft: PassageDraft?
  @State private var passageBar = PassagePopover()
  @State private var marks: [ReaderMark] = []
  @State private var placedNotes: [PlacedNote] = []

  init(
    content: ContentRef, title: String?, markdown: String, byline: NSAttributedString? = nil,
    images: [String: NSImage] = [:], serif: Bool = false, pane: PaneWidth = .panel, language: ArticleLanguage? = nil,
    openingQuote: TextQuote? = nil, placeholder: FetchingItem? = nil, cite: ((URL) -> Int?)? = nil,
    openWeb: ((URL) -> Void)? = nil, showsProgress: Bool = false, @ViewBuilder ending: () -> Ending
  ) {
    self.cite = cite
    self.openWeb = openWeb
    self.showsProgress = showsProgress
    self.ending = ending()
    self.language = language
    self.openingQuote = openingQuote
    self.placeholder = placeholder
    self.byline = byline
    self.images = images
    self.serif = serif
    self.pane = pane
    _panelWidth = AppStorage(wrappedValue: Double(pane.ideal), pane.key)
    self.content = content
    self.title = title
    self.markdown = Self.titled(markdown, title)
  }

  private var item: EntityID? { content.item }

  /// Only an item has key points to open.
  private var keyPointOpener: ((KeyPoint) -> Void)? {
    guard item != nil else { return nil }
    return { open($0) }
  }

  var body: some View {
    let width = beside ? pane.fitting(panelWidth, in: available) : pane.overlaid(panelWidth, in: available)
    SidePanel(open: panelOpen, beside: beside, width: width, expand: openPanel) {
      reader
        .animation(placeholder != nil && !reduceMotion ? Motion.standard : nil, value: text != nil)
    } panel: {
      ReaderPanel(
        content: content, notes: placedNotes, keyPoints: keyPoints?.value, openKeyPoint: keyPointOpener, tab: $tab,
        draft: $draft, chosen: chosen, reveal: show, revealPassage: show,
        ask: { placed in ask(placed.note.locator, excerpt: placed.note.excerpt) }, collapse: closePanel
      )
      .overlay(alignment: .leading) {
        if beside {
          PaneResizer(pane: pane, width: $panelWidth, maximum: pane.fitting(.infinity, in: available))
        }
      }
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      available = $0
    }
    .task(id: content) {
      if standIns?.moment?.panel == .highlights { tab = .highlights }
      if standIns?.moment?.panel == .keyPoints { tab = .keyPoints }
      if standIns?.moment?.onlyKeyPoints == true { onlyKeyPoints = true }
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
    .task(id: item) {
      guard let item else { return }
      for await delivered in host.subscribe(ItemKeyPoints(item: item)) { keyPoints = delivered }
    }
  }

  private var points: [KeyPoint] { keyPoints?.value?.keyPoints?.points ?? [] }

  @ViewBuilder private var reader: some View {
    if onlyKeyPoints, !points.isEmpty {
      KeyPassagesReader(title: title, markdown: markdown, points: points, revealed: revealedKey)
        .overlay(alignment: .topTrailing) { corner }
    } else if let text {
      Reader(
        text: text, start: start, width: readingWidth, marks: marks, reveal: reveal, selected: standIns?.selection,
        events: events, passageBar: passageBar
      )
      .transition(.opacity)
      .onDisappear { passageBar.close() }
      .overlay(alignment: .topTrailing) { corner }
      .overlay(alignment: .top) {
        if showsProgress { ReadingLine(share: standIns?.readThrough ?? progress) }
      }
      .overlay(alignment: .bottom) {
        if ended || standIns?.endInView == true {
          ending.transition(.offset(y: 30).combined(with: .opacity))
        }
      }
    } else if let placeholder {
      placeholder
    } else {
      Palette.canvas
    }
  }

  /// The top corner over the text: playing only the key points, and translating.
  private var corner: some View {
    HStack(spacing: Spacing.xs) {
      if !points.isEmpty { OnlyKeyPointsPill(on: $onlyKeyPoints) }
      if let language, !onlyKeyPoints {
        TranslateButton(language: language, mode: $mode) {
          if let item { Task { _ = try? await host.run(TranslateArticle(item: item)) } }
        }
      }
    }
    .padding(.top, Spacing.xs)
    .padding(.trailing, panelOpen ? Spacing.s : Spacing.s * 2 + Size.iconButton)
  }

  private var beside: Bool { pane.fitsBeside(in: available) }

  private var panelOpen: Bool { beside ? panelShown : floating }

  private func openPanel() {
    withAnimation(Motion.fold) {
      panelShown = true
      floating = true
    }
  }

  private func closePanel() {
    withAnimation(Motion.fold) {
      if beside { panelShown = false }
      floating = false
    }
  }

  private var shownTranslation: ShownTranslation? {
    language?.shown(mode, order: style.order)
  }

  /// Brings a key passage into view and flashes it.
  private func open(_ point: KeyPoint) {
    guard let passage = point.passage else { return }
    if onlyKeyPoints {
      let number = (points.firstIndex(of: point) ?? 0) + 1
      revealedKey = (number, (revealedKey?.serial ?? 0) + 1)
    } else if let text {
      let original = text.map.isIdentity ? text.plain : text.map.original
      if let range = KeyPassageLayout.range(of: passage.text, in: original) { show(text.map.shown(range)) }
    }
  }

  private func setText() -> ReadingText {
    ReadingText(
      markdown: markdown, byline: byline, images: images, serif: serif, translation: shownTranslation, cite: cite)
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
        withAnimation(Motion.rise) { ended = true }
        Task { _ = try? await host.run(MarkRead(content: content)) }
      },
      scrolledThrough: { share in if showsProgress { progress = share } },
      openLink: { url in
        if let locator = Locator(url.absoluteString) {
          openPage.follow(locator, in: content.conversation, reveal: show)
        } else if url.isWebLink {
          if let openWeb { openWeb(url) } else { NSWorkspace.shared.open(url) }
        }
      },
      passage: passageActions,
      noteClicked: { note in
        openPanel()
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
    openPanel()
  }

  private func passage(_ range: NSRange) -> (locator: Locator, excerpt: String)? {
    guard let passage = text?.quote(range) else { return nil }
    return (Locator(passage.quote, in: content), passage.excerpt)
  }
}

extension ContentReader where Ending == EmptyView {
  init(
    content: ContentRef, title: String?, markdown: String, byline: NSAttributedString? = nil,
    images: [String: NSImage] = [:], serif: Bool = false, pane: PaneWidth = .panel, language: ArticleLanguage? = nil,
    openingQuote: TextQuote? = nil, placeholder: FetchingItem? = nil
  ) {
    self.init(
      content: content, title: title, markdown: markdown, byline: byline, images: images, serif: serif, pane: pane,
      language: language, openingQuote: openingQuote, placeholder: placeholder
    ) { EmptyView() }
  }
}

extension ContentRef {
  /// The item this is, when it is one.
  var item: EntityID? {
    if case .item(let item) = self { return item }
    return nil
  }

  /// The lesson this is, when it is one.
  var lesson: Lesson.ID? {
    if case .lesson(_, let lesson) = self { return lesson }
    return nil
  }

  /// The conversation about it: an item's own, or its course's.
  var conversation: ConversationRef {
    switch self {
    case .item(let item): .item(item)
    case .lesson(let course, _): .course(course)
    }
  }
}

extension Page {
  init?(_ content: ContentRef) {
    guard case .item(let item) = content else { return nil }
    self = .item(item)
  }
}

/// Opens a page on top of the current place, as following a link does.
struct OpenPage {
  let action: (Page) -> Void

  func callAsFunction(_ page: Page) {
    action(page)
  }

  @MainActor func follow(_ locator: Locator, in conversation: ConversationRef, reveal: @MainActor (Locator) -> Void) {
    switch locator.content {
    case .item(let item):
      if conversation == .item(item) {
        reveal(locator)
      } else {
        action(.passage(locator))
      }
    case .lesson(let course, _) where conversation == .course(course):
      reveal(locator)
    case .lesson:
      break
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
