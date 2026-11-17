import AppKit
import LociModel
import SwiftUI

/// A lesson's or an item's Markdown in the reader with the panel beside it. It opens where the reader last
/// was, remembers where they go and whether they reached the end, and shows the notes left on it.
struct ContentReader<Extra: View>: View {
  @Environment(\.host) private var host
  @Environment(\.openPage) private var openPage
  let content: ContentRef
  let markdown: String
  let glossary: Glossary
  /// The Markdown the reader saw before the mentor's latest revision; what changed since is marked.
  let previous: String?
  let reachedEnd: () -> Void
  /// Shown under the headings on the panel's contents page.
  let extra: () -> Extra
  @State private var text: ReadingText?
  @State private var start: TextQuote?
  @State private var notes: Feed<[Note]>?
  @State private var pending: Feed<[PendingAnswer]>?
  @State private var reveal: Reveal?
  @State private var tab = PanelTab.contents
  @State private var focusedNote: EntityID?
  @State private var panelShown = true
  @State private var marks: [ReaderMark] = []
  @State private var placedNotes: [PlacedNote] = []

  init(
    content: ContentRef, markdown: String, glossary: Glossary = .empty, previous: String? = nil,
    reachedEnd: @escaping () -> Void = {}, @ViewBuilder extra: @escaping () -> Extra
  ) {
    self.content = content
    self.markdown = markdown
    self.glossary = glossary
    self.previous = previous
    self.reachedEnd = reachedEnd
    self.extra = extra
  }

  var body: some View {
    Group {
      if let text {
        Reader(text: text, start: start, marks: marks, reveal: reveal, events: events)
      } else {
        Palette.canvas
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
    .onChange(of: pending) { remark() }
    .subscribing(NotesOn(content: content), into: $notes)
    .subscribing(PendingAnswers(content: content), into: $pending)
    .inspector(isPresented: $panelShown) {
      ReaderPanel(
        content: content, headings: text?.headings ?? [], notes: placedNotes, pending: pending?.value ?? [],
        tab: $tab, focusedNote: focusedNote, reveal: show, extra: extra
      )
      .inspectorColumnWidth(Size.panelWidth)
    }
    .toolbar {
      ToolbarItem {
        Button {
          panelShown.toggle()
        } label: {
          Label {
            Text(.loci("panel.toggle"))
          } icon: {
            Image(systemName: Symbols.panel)
          }
        }
      }
    }
  }

  /// Works out again where notes sit and what to mark, after the text or anything marked on it changed.
  private func remark() {
    guard let text else { return }
    var lesson: Lesson.Slug?
    if case .lesson(let ref) = content { lesson = ref.lesson }
    placedNotes = PlacedNote.place(notes?.value ?? [], in: text)
    let revised = previous.map { ReaderMark.revisions(from: ReadingText(markdown: $0), to: text) } ?? []
    let asked = Set((pending?.value ?? []).map(\.note))
    marks =
      revised + ReaderMark.terms(of: glossary, in: text, lesson: lesson)
      + PlacedNote.marks(placedNotes, pending: asked)
  }

  private func show(_ range: NSRange) {
    reveal = Reveal(range: range, serial: (reveal?.serial ?? 0) + 1)
  }

  private var events: ReaderEvents {
    ReaderEvents(
      moved: { quote in
        Task { _ = try? await host.run(SaveReadingPosition(content: content, position: Locator(quote, in: content))) }
      },
      reachedEnd: {
        reachedEnd()
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
        panelShown = true
        tab = .notes
        focusedNote = note
      })
  }

  /// Highlighting, writing a thought, and, in a lesson, asking its mentor.
  private var passageActions: PassageActions {
    var actions = PassageActions(
      highlight: { range in leaveNote(on: range, thought: nil) },
      think: { range, thought in leaveNote(on: range, thought: thought) })
    if case .lesson(let lesson) = content {
      actions.ask = { range, question in
        guard let passage = passage(range) else { return }
        tab = .notes
        panelShown = true
        Task {
          _ = try? await host.run(
            AskAboutPassage(
              mentor: lesson.mentor, locator: passage.locator, excerpt: passage.excerpt, question: question))
        }
      }
    }
    return actions
  }

  private func leaveNote(on range: NSRange, thought: String?) {
    guard let passage = passage(range) else { return }
    if thought != nil {
      tab = .notes
      panelShown = true
    }
    Task { _ = try? await host.run(AddNote(locator: passage.locator, excerpt: passage.excerpt, thought: thought)) }
  }

  private func passage(_ range: NSRange) -> (locator: Locator, excerpt: String)? {
    guard let plain = text?.plain, let words = Range(range, in: plain),
      let quote = try? TextQuote(quoting: words, in: plain)
    else { return nil }
    return (Locator(quote, in: content), String(plain[words]))
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

/// Opens a page on top of the current place, as following a link does, or in place of the page on top,
/// as going on to the next lesson does.
struct OpenPage {
  let action: (Page, _ replacing: Bool) -> Void

  func callAsFunction(_ page: Page, replacing: Bool = false) {
    action(page, replacing)
  }
}

extension EnvironmentValues {
  @Entry var openPage = OpenPage { _, _ in }
}
