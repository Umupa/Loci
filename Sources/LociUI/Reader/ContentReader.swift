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
  @State private var text: ReadingText?
  @State private var start: TextQuote?

  var body: some View {
    Group {
      if let text {
        Reader(text: text, start: start, events: events)
      } else {
        Palette.canvas
      }
    }
    .task(id: content) {
      start = (try? await host.run(ReadReadingState(content: content)))?.position?.quote
      text = ReadingText(markdown: markdown)
    }
    .onChange(of: markdown) {
      if text != nil { text = ReadingText(markdown: markdown) }
    }
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

/// Opens a page on top of the current place, as following a link does.
struct OpenPage {
  let action: (Page) -> Void

  func callAsFunction(_ page: Page) {
    action(page)
  }
}

extension EnvironmentValues {
  @Entry var openPage = OpenPage { _ in }
}
