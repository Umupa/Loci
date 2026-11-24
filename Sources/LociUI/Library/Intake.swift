import Foundation
import LociModel
import SwiftUI

/// Something waiting in the import panel to be taken in.
enum PendingImport: Hashable, Identifiable {
  /// A video or episode link.
  case link(URL)
  /// Several videos chosen on one page of the built-in browser, taken in together.
  case links([URL])
  /// Video or audio files on this Mac, taken in together.
  case files([URL])

  var id: Self { self }
}

/// Takes in what is pasted, typed, dropped or chosen, without leaving the page: a video or episode link and
/// video or audio files wait in the import panel; an article, a paper, a text file or a book goes straight in.
struct TakeIn {
  let host: any LociModel.Host
  let ask: @MainActor (PendingImport) -> Void
  let failed: @MainActor (HostError) -> Void

  @MainActor
  func link(_ url: URL) {
    switch LinkKind(url) {
    case .video, .audio: ask(.link(url))
    case .article, .paper: run { () async throws(HostError) in _ = try await host.run(AddLink(url: url)) }
    }
  }

  /// Videos found on a page of the built-in browser: they wait in the import panel whatever their address says.
  @MainActor
  func videos(_ links: [URL]) {
    guard let first = links.first else { return }
    ask(links.count == 1 ? .link(first) : .links(links))
  }

  @MainActor
  func files(media: [URL], text: [TextFile], books: [URL]) {
    if !text.isEmpty {
      run { () async throws(HostError) in
        for file in text { _ = try await host.run(AddTextItem(fileName: file.fileName, text: file.text)) }
      }
    }
    for book in books {
      run { () async throws(HostError) in _ = try await self.book(book) }
    }
    if !media.isEmpty { ask(.files(media)) }
  }

  /// Sends an EPUB or text file to the host and takes it in as a book.
  @MainActor
  func book(_ file: URL) async throws(HostError) -> Item {
    try await host.run(ImportBook(upload: try await host.upload(LocalFile(file))))
  }

  @MainActor
  func dropped(_ dropped: [Dropped]) {
    var media: [URL] = []
    var text: [TextFile] = []
    var books: [URL] = []
    for each in dropped {
      switch each {
      case .link(let url): link(url)
      case .textFile(let file): text.append(file)
      case .mediaFile(let file): media.append(file)
      case .bookFile(let file): books.append(file)
      }
    }
    files(media: media, text: text, books: books)
  }

  @MainActor
  private func run(_ work: @escaping @MainActor () async throws(HostError) -> Void) {
    Task {
      do throws(HostError) {
        try await work()
      } catch {
        failed(error)
      }
    }
  }
}

extension EnvironmentValues {
  /// Set by the window; `nil` where nothing can be taken in.
  @Entry var takeIn: TakeIn?
}

extension View {
  /// Lets the views inside take things in, while the Mac behind the window takes changes.
  func takingIn(_ takeIn: TakeIn) -> some View {
    modifier(TakingIn(takeIn: takeIn))
  }
}

private struct TakingIn: ViewModifier {
  @Environment(\.changesAllowed) private var changesAllowed
  let takeIn: TakeIn

  func body(content: Content) -> some View {
    content.environment(\.takeIn, changesAllowed ? takeIn : nil)
  }
}
