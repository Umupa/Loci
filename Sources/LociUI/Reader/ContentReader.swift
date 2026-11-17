import AppKit
import LociModel
import SwiftUI

/// A lesson's or an item's Markdown in the reader, opening where the reader last was in it and remembering
/// where they go and whether they reached the end.
struct ContentReader: View {
  @Environment(\.host) private var host
  @Environment(\.openPage) private var openPage
  let content: ContentRef
  let markdown: String
  var glossary: Glossary = .empty
  /// The Markdown the reader saw before the mentor's latest revision; what changed since is marked.
  var previous: String?
  var reachedEnd: () -> Void = {}
  @State private var text: ReadingText?
  @State private var start: TextQuote?
  @State private var marks: [ReaderMark] = []

  var body: some View {
    Group {
      if let text {
        Reader(text: text, start: start, marks: marks, events: events)
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
  }

  private func remark() {
    guard let text else { return }
    var lesson: Lesson.Slug?
    if case .lesson(let ref) = content { lesson = ref.lesson }
    let revised = previous.map { ReaderMark.revisions(from: ReadingText(markdown: $0), to: text) } ?? []
    marks = revised + ReaderMark.terms(of: glossary, in: text, lesson: lesson)
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
      })
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
