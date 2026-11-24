import AppKit
import LociModel
import SwiftUI

/// A book, page by page: two pages side by side in a wide window, one in a narrow one, with its table of
/// contents, reading settings and a bar across the whole book. No panel, no conversation.
struct BookScreen: View {
  @Environment(\.host) private var host
  let item: Item
  @State private var opened: Opened?

  enum Opened {
    case reading(BookContents, BookSpot?)
    case unreadable
  }

  var body: some View {
    Group {
      switch opened {
      case .reading(let contents, let spot):
        BookPages(item: item, contents: contents, start: spot, files: BookFiles(item: item.id, host: host))
      case .unreadable:
        Text(.loci("book.unreadable"))
          .font(Typography.body)
          .foregroundStyle(Palette.inkMuted)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case nil:
        Palette.canvas
      }
    }
    .background(Palette.canvas)
    .task(id: item.id) { await open() }
  }

  private func open() async {
    guard let contents = try? await host.run(ReadBookContents(item: item.id)) else {
      opened = .unreadable
      return
    }
    let state = try? await host.run(ReadReadingState(content: .item(item.id)))
    var spot: BookSpot?
    if case .item(_, .spot(let saved)) = state?.position { spot = saved }
    opened = .reading(contents, spot)
  }
}

/// The pages themselves, once the book's contents are known.
struct BookPages: View {
  @Environment(\.host) private var host
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.openURL) private var openURL
  @AppStorage(BookSettings.sizeKey) private var size = BookSettings.standard.size
  @AppStorage(BookSettings.spacingKey) private var spacing = BookSettings.standard.spacing
  @AppStorage(BookSettings.faceKey) private var face = BookSettings.standard.face
  let item: Item
  let contents: BookContents
  let start: BookSpot?
  let files: BookFiles
  @State private var reader: BookReader?
  @State private var width: Double = 0
  @State private var saving: Task<Void, Never>?

  var settings: BookSettings { BookSettings(size: size, spacing: spacing, face: face) }

  var body: some View {
    GeometryReader { frame in
      ZStack {
        if let reader {
          BookWebView(webView: reader.webView)
          BookChrome(reader: reader, size: $size, spacing: $spacing, face: $face)
        }
      }
      .onChange(of: frame.size.width, initial: true) { width = frame.size.width }
    }
    .task(id: width > 0) { await begin() }
    .onChange(of: layout) { _, layout in Task { await reader?.relayout(layout) } }
    .onDisappear {
      saving?.cancel()
      if let spot = reader?.spot { save(spot) }
    }
  }

  private var layout: BookLayout { BookLayout(settings: settings, dark: colorScheme == .dark, width: width) }

  private func begin() async {
    guard width > 0, reader == nil else { return }
    let reader = BookReader(item: item.id, contents: contents, files: files, layout: layout)
    reader.moved = { spot in
      saving?.cancel()
      saving = Task {
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        save(spot)
      }
    }
    reader.finished = { [host, id = item.id] in Task { _ = try? await host.run(MarkRead(content: .item(id))) } }
    reader.openLink = { openURL($0) }
    self.reader = reader
    await reader.open(at: start)
    reader.webView.window?.makeFirstResponder(reader.webView)
  }

  private func save(_ spot: BookSpot) {
    let position = Locator.item(item.id, .spot(spot))
    Task { [host, id = item.id] in _ = try? await host.run(SaveReadingPosition(content: .item(id), position: position))
    }
  }
}

/// The reader's web view, as it is: the reader decides what it shows.
struct BookWebView: NSViewRepresentable {
  let webView: NSView

  func makeNSView(context: Context) -> NSView { webView }
  func updateNSView(_ view: NSView, context: Context) {}
}
