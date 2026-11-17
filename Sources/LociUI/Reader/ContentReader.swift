import AppKit
import LociModel
import SwiftUI

/// A lesson's or an item's Markdown in the reader with the panel beside it. It opens where the reader last
/// was, remembers where they go and whether they reached the end, and shows the highlights left on it. A
/// lesson's panel also holds the conversation with its mentor.
struct ContentReader<Extra: View>: View {
  @Environment(\.host) private var host
  @Environment(\.openPage) private var openPage
  let content: ContentRef
  /// Set over the text, unless the text starts with a title of its own.
  let title: String?
  let markdown: String
  let glossary: Glossary
  /// The Markdown the reader saw before the mentor's latest revision; what changed since is marked.
  let previous: String?
  /// Shown under the highlights in the panel.
  let extra: () -> Extra
  @State private var text: ReadingText?
  @State private var start: TextQuote?
  @State private var notes: Feed<[Note]>?
  @State private var mentor: Feed<MentorPage>?
  @State private var conversation: Feed<Conversation>?
  @State private var reveal: Reveal?
  @State private var tab = PanelTab.conversation
  @State private var chosen: ChosenNote?
  @State private var panelShown = true
  @State private var available = CGFloat.infinity
  @AppStorage(PaneWidth.panel.key) private var panelWidth = Double(PaneWidth.panel.ideal)
  @AppStorage(ReadingWidth.key) private var readingWidth = ReadingWidth.comfortable
  @State private var draft: PassageDraft?
  @State private var marks: [ReaderMark] = []
  @State private var placedNotes: [PlacedNote] = []

  init(
    content: ContentRef, title: String?, markdown: String, glossary: Glossary = .empty, previous: String? = nil,
    @ViewBuilder extra: @escaping () -> Extra
  ) {
    self.content = content
    self.title = title
    self.markdown = Self.titled(markdown, title)
    self.glossary = glossary
    self.previous = previous.map { Self.titled($0, title) }
    self.extra = extra
  }

  var body: some View {
    HStack(spacing: 0) {
      reader
      if panelShown {
        ReaderPanel(
          content: content, mentor: mentor?.value?.mentor, conversation: conversation?.value, notes: placedNotes,
          tab: $tab, draft: $draft, chosen: chosen, reveal: show, revealPassage: show,
          ask: { placed in ask(placed.note.locator, excerpt: placed.note.excerpt) },
          collapse: { withAnimation(Motion.fold) { panelShown = false } }, extra: extra
        )
        .frame(width: PaneWidth.panel.fitting(panelWidth, in: available))
        .overlay(alignment: .leading) {
          PaneResizer(
            pane: .panel, width: $panelWidth, maximum: PaneWidth.panel.fitting(.infinity, in: available))
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
      start = (try? await host.run(ReadReadingState(content: content)))?.position?.quote
      text = ReadingText(markdown: markdown)
      remark()
    }
    .onChange(of: markdown) {
      guard text != nil else { return }
      text = ReadingText(markdown: markdown)
      remark()
    }
    .onChange(of: previous) { remark() }
    .onChange(of: glossary) { remark() }
    .onChange(of: notes) { remark() }
    .subscribing(NotesOn(content: content), into: $notes)
    .modifier(MentorFeeds(content: content, mentor: $mentor, conversation: $conversation))
  }

  @ViewBuilder private var reader: some View {
    if let text {
      Reader(text: text, start: start, width: readingWidth, marks: marks, reveal: reveal, events: events)
    } else {
      Palette.canvas
    }
  }

  private static func titled(_ markdown: String, _ title: String?) -> String {
    guard let title, !markdown.hasPrefix("# ") else { return markdown }
    return "# \(title)\n\n" + markdown
  }

  /// Works out again where highlights sit and what to mark, after the text or anything marked on it changed.
  private func remark() {
    guard let text else { return }
    var lesson: Lesson.Slug?
    if case .lesson(let ref) = content { lesson = ref.lesson }
    placedNotes = PlacedNote.place(notes?.value ?? [], in: text)
    let revised = previous.map { ReaderMark.revisions(from: ReadingText(markdown: $0), to: text) } ?? []
    marks = revised + ReaderMark.terms(of: glossary, in: text, lesson: lesson) + PlacedNote.marks(placedNotes)
  }

  private func show(_ range: NSRange) {
    reveal = Reveal(range: range, serial: (reveal?.serial ?? 0) + 1)
  }

  private func show(_ locator: Locator) {
    guard let plain = text?.plain, let words = locator.quote?.range(in: plain) else { return }
    show(NSRange(words, in: plain))
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
          openPage(Page(locator.content))
        } else if url.isWebLink {
          NSWorkspace.shared.open(url)
        }
      },
      openTerm: { term in
        guard case .lesson(let ref) = content, let lesson = term.lesson else { return }
        openPage(.lesson(LessonRef(mentor: ref.mentor, lesson: lesson)))
      },
      passage: passageActions,
      noteClicked: { note in
        withAnimation(Motion.fold) { panelShown = true }
        tab = .highlights
        chosen = ChosenNote(note: note, serial: (chosen?.serial ?? 0) + 1)
        if let range = placedNotes.first(where: { $0.id == note })?.range { show(range) }
      })
  }

  /// Highlighting with an optional thought, and, where there is a mentor, asking it.
  private var passageActions: PassageActions {
    PassageActions(
      highlight: { range in
        guard let passage = passage(range) else { return nil }
        return try? await host.run(AddNote(locator: passage.locator, excerpt: passage.excerpt)).id
      },
      think: { note, thought in
        Task { _ = try? await host.run(SetNoteThought(content: content, note: note, thought: thought)) }
      },
      ask: mentor?.value == nil
        ? nil
        : { range in
          guard let passage = passage(range) else { return }
          ask(passage.locator, excerpt: passage.excerpt)
        })
  }

  /// Puts the passage above the mentor's composer and turns the panel to the conversation.
  private func ask(_ locator: Locator, excerpt: String?) {
    draft = PassageDraft(content: content, locator: locator, excerpt: excerpt ?? locator.quote?.text ?? "")
    tab = .conversation
    withAnimation(Motion.fold) { panelShown = true }
  }

  private func passage(_ range: NSRange) -> (locator: Locator, excerpt: String)? {
    guard let plain = text?.plain, let words = Range(range, in: plain),
      let quote = try? TextQuote(quoting: words, in: plain)
    else { return nil }
    return (Locator(quote, in: content), String(plain[words]))
  }
}

/// A lesson's mentor and the conversation with it; an item has neither.
private struct MentorFeeds: ViewModifier {
  let content: ContentRef
  @Binding var mentor: Feed<MentorPage>?
  @Binding var conversation: Feed<Conversation>?

  func body(content view: Content) -> some View {
    if case .lesson(let lesson) = content {
      view
        .subscribing(OneMentor(mentor: lesson.mentor), into: $mentor)
        .subscribing(MentorConversation(mentor: lesson.mentor), into: $conversation)
    } else {
      view
    }
  }
}

extension Page {
  init(_ content: ContentRef) {
    switch content {
    case .item(let item): self = .item(item)
    case .lesson(let lesson): self = .lesson(lesson)
    }
  }
}

/// Opens a page on top of the current place, as following a link does.
struct OpenPage {
  let action: (Page) -> Void

  func callAsFunction(_ page: Page) {
    action(page)
  }
}

/// Goes to a place in the sidebar, as choosing a course on a mentor's shelf does.
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
