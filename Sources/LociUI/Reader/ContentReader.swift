import AppKit
import LociModel
import SwiftUI

/// Markdown to read — an item's text or a lesson — with Loci's panel beside it. It opens where the reader last
/// was, remembers where they go and whether they reached the end, and shows the highlights left on it.
struct ContentReader: View {
  @Environment(\.host) private var host
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.openPage) private var openPage
  @Environment(\.peekLink) private var peekLink
  @Environment(\.standIns) private var standIns
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.showFailure) private var showFailure
  let content: ContentRef
  /// The item being read, for the thought on the whole of it; `nil` for a lesson.
  let item: Item?
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
  /// Where tidying the article stands; `nil` for text that is not an article.
  let tidiness: ArticleTidiness?
  let openingQuote: TextQuote?
  let placeholder: FetchingItem?
  /// The number of the source a link cites, for text whose links to its sources are citations.
  let cite: ((URL) -> Int?)?
  /// Whether a thin amber line along the top shows how far down the text has been read.
  let showsProgress: Bool
  private let renderMermaid: MermaidRenderer.Render
  @State private var progress = 0.0
  @AppStorage(SubtitleMode.key) private var mode = SubtitleMode.both
  @AppStorage(SubtitleStyle.key) private var style = SubtitleStyle.standard
  @State private var keyPoints: Feed<KeyPointsPage>?
  @State private var onlyKeyPoints = false
  @State private var revealedKey: (number: Int, serial: Int)?
  @State private var text: ReadingText?
  @State private var mermaidImages: [String: NSImage] = [:]
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
    content: ContentRef, item: Item? = nil, title: String?, markdown: String, byline: NSAttributedString? = nil,
    images: [String: NSImage] = [:], serif: Bool = false, pane: PaneWidth = .panel, language: ArticleLanguage? = nil,
    tidiness: ArticleTidiness? = nil, openingQuote: TextQuote? = nil, placeholder: FetchingItem? = nil,
    cite: ((URL) -> Int?)? = nil,
    showsProgress: Bool = false, renderMermaid: @escaping MermaidRenderer.Render = MermaidRenderer.render
  ) {
    self.cite = cite
    self.showsProgress = showsProgress
    self.renderMermaid = renderMermaid
    self.language = language
    self.tidiness = tidiness
    self.openingQuote = openingQuote
    self.placeholder = placeholder
    self.byline = byline
    self.images = images
    self.serif = serif
    self.pane = pane
    _panelWidth = AppStorage(wrappedValue: Double(pane.ideal), pane.key)
    self.content = content
    self.item = item
    self.title = title
    self.markdown = Self.titled(markdown, title)
  }

  private var itemID: EntityID? { content.item }

  /// Only an item has key points to open.
  private var keyPointOpener: ((KeyPoint) -> Void)? {
    guard itemID != nil else { return nil }
    return { open($0) }
  }

  var body: some View {
    let width = beside ? pane.fitting(panelWidth, in: available) : pane.overlaid(panelWidth, in: available)
    SidePanel(open: panelOpen, beside: beside, width: width, expand: openPanel) {
      reader
        .animation(placeholder != nil && !reduceMotion ? Motion.standard : nil, value: text != nil)
    } panel: {
      ReaderPanel(
        content: content, item: item, whole: notes?.value?.first(where: \.isWhole), notes: placedNotes,
        images: images, keyPoints: keyPoints?.value, openKeyPoint: keyPointOpener, tab: $tab, draft: $draft,
        chosen: chosen, reveal: show, revealPassage: show, ask: ask, collapse: closePanel
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
      if text == nil, let openingQuote, let original = loaded.originalRange(of: openingQuote) {
        start = openingQuote
        show(loaded.map.shown(original), original: original)
      } else {
        start = saved
      }
      text = loaded
      remark()
    }
    .onChange(of: markdown) { refreshText() }
    .onChange(of: images.keys.sorted()) { refreshText() }
    .onChange(of: shownTranslation) { refreshText() }
    .onChange(of: mermaidImages) { refreshText() }
    .task(id: mermaidRequest) {
      let request = mermaidRequest
      let images = await renderMermaid(request.sources.sorted(), request.dark)
      guard !Task.isCancelled, !images.isEmpty || !mermaidImages.isEmpty else { return }
      mermaidImages = images
    }
    .onChange(of: notes) { remark() }
    .subscribing(NotesOn(content: content), into: $notes)
    .task(id: itemID) {
      guard let item = itemID else { return }
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
    } else if let placeholder {
      placeholder
    } else {
      Palette.canvas
    }
  }

  /// The top corner over the text: playing only the key points, tidying and translating. One of the two waits
  /// while the other runs.
  private var corner: some View {
    HStack(spacing: Spacing.xs) {
      if !points.isEmpty { OnlyKeyPointsButton(on: $onlyKeyPoints) }
      if let tidiness, !onlyKeyPoints {
        TidyButton(progress: tidiness.progress, translating: language?.running ?? false) {
          guard let itemID else { return }
          Task {
            do throws(HostError) {
              _ = try await host.run(TidyArticle(item: itemID))
            } catch {
              showFailure(error)
            }
          }
        }
      }
      if let language, !onlyKeyPoints {
        TranslateButton(language: language, mode: $mode) {
          if let itemID { Task { _ = try? await host.run(TranslateArticle(item: itemID)) } }
        }
        .disabled(tidiness?.running ?? false)
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
      if let range = KeyPassageLayout.range(of: passage.text, in: original) {
        show(text.map.shown(range), original: range)
      }
    }
  }

  private func setText() -> ReadingText {
    ReadingText(
      markdown: markdown, byline: byline, images: images, serif: serif, translation: shownTranslation, cite: cite,
      diagrams: mermaidImages)
  }

  private struct MermaidRequest: Equatable {
    let sources: Set<String>
    let dark: Bool
  }

  private func refreshText() {
    guard text != nil else { return }
    text = setText()
    remark()
  }

  private var mermaidRequest: MermaidRequest {
    MermaidRequest(sources: text?.mermaidSources ?? [], dark: colorScheme == .dark)
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

  private func show(_ range: NSRange, original: NSRange?) {
    reveal = Reveal(range: range, serial: (reveal?.serial ?? 0) + 1, original: original)
  }

  private func show(_ note: PlacedNote) {
    if let range = note.range { show(range, original: note.original) }
  }

  private func show(_ locator: Locator) {
    guard let text, let quote = locator.quote, let original = text.originalRange(of: quote) else { return }
    show(text.map.shown(original), original: original)
  }

  private var events: ReaderEvents {
    ReaderEvents(
      moved: { quote in
        Task { _ = try? await host.run(SaveReadingPosition(content: content, position: Locator(quote, in: content))) }
      },
      reachedEnd: {
        Task { _ = try? await host.run(MarkRead(content: content)) }
      },
      scrolledThrough: { share in if showsProgress { progress = share } },
      openLink: { url in
        if let locator = Locator(url.absoluteString) {
          openPage.follow(locator, in: content.conversation, reveal: show)
        } else if url.isWebLink {
          peekLink?(url)
        }
      },
      passage: passageActions(original: false),
      tablePassage: passageActions(original: true),
      noteClicked: { choose($0, writing: false) },
      pictureHighlighted: { choose($0, writing: true) })
  }

  /// Turns the panel to the highlight's card; `writing` readies its field for typing.
  private func choose(_ note: EntityID, writing: Bool) {
    openPanel()
    tab = .highlights
    chosen = ChosenNote(note: note, serial: (chosen?.serial ?? 0) + 1, writing: writing)
  }

  /// Highlighting with an optional thought, and asking Loci about it.
  private func passageActions(original: Bool) -> PassageActions {
    PassageActions(
      highlight: { range in
        guard let passage = original ? text?.quoteOriginal(range) : text?.quote(range) else { return nil }
        return try? await host.run(
          AddNote(locator: Locator(passage.quote, in: content), excerpt: passage.excerpt, pictures: passage.pictures)
        ).id
      },
      ask: { range in
        guard let passage = original ? text?.quoteOriginal(range) : text?.quote(range) else { return }
        ask(Locator(passage.quote, in: content), excerpt: passage.excerpt, pictures: passage.pictures)
      },
      note: .on(content, host: host, changesAllowed: changesAllowed) { note in
        if let placed = placedNotes.first(where: { $0.id == note }) { ask(placed) }
      }, changes: changesAllowed)
  }

  private func ask(_ placed: PlacedNote) {
    ask(placed.note.locator, excerpt: placed.words, pictures: placed.pictures)
  }

  /// Puts the passage above Loci's composer and turns the panel to the conversation.
  private func ask(_ locator: Locator, excerpt: String?, pictures: [String]) {
    draft = PassageDraft(
      content: content, locator: locator, excerpt: excerpt ?? (pictures.isEmpty ? locator.quote?.text ?? "" : ""),
      pictures: pictures)
    tab = .conversation
    openPanel()
  }
}
