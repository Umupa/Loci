import LociModel
import SwiftUI

/// Items Loci put into the library one after another, as library cards: one, or a stack of them. Each says
/// where its work stands while it goes on, opens its item, and can be taken back out of the library from its
/// menu. Items deleted since show as faint lines under the cards.
struct SavedItemsCard: View {
  @Environment(\.openPage) private var openPage
  @Environment(\.host) private var host
  let items: [EntityID]
  @State private var library: Feed<[Item]>?
  @State private var jobs: Feed<[Job]>?
  @State private var titles: [EntityID: String] = [:]

  var body: some View {
    let lines = Self.lines(items, library: library?.value, jobs: jobs?.value ?? [], titles: titles)
    let shown = lines.compactMap { if case .shown(let item, let work) = $0 { (item, work) } else { nil } }
    let deleted = lines.filter { if case .deleted = $0 { true } else { false } }
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      if !shown.isEmpty {
        CardStack(cards: shown) { line, showsWords in
          LibraryCard(
            item: line.0, line: SavedItemLine.text(line.0, work: line.1), showsWords: showsWords,
            progress: SavedItemLine.progress(line.1)
          )
          .contextMenu {
            Button(.loci("added.undo")) { Task { _ = try? await host.run(DeleteItems([line.0.id])) } }
              .changesData()
          }
        } open: { line in
          openPage(.item(line.0.id))
        }
      }
      ForEach(Array(deleted.enumerated()), id: \.offset) { _, line in
        if case .deleted(let title) = line { DeletedItemLine(title: title) }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .subscribing(AllItems(), into: $library)
    .subscribing(AllJobs(), into: $jobs)
    .onChange(of: library?.value, initial: true) { _, items in
      for item in items ?? [] where self.items.contains(item.id) { titles[item.id] = item.title }
    }
  }

  /// What a card shows of one item.
  enum Line: Equatable {
    /// In the library, with where its work stands; finished work says nothing.
    case shown(Item, JobLine)
    /// No longer in the library; the title is known when the card saw the item before it went.
    case deleted(title: String?)
  }

  /// Each item in order, once the library is known; nothing before.
  nonisolated static func lines(_ items: [EntityID], library: [Item]?, jobs: [Job], titles: [EntityID: String])
    -> [Line]
  {
    guard let library else { return [] }
    return items.map { id in
      guard let item = library.first(where: { $0.id == id }) else { return .deleted(title: titles[id]) }
      return .shown(item, JobLine(jobs.first { $0.item == id }))
    }
  }
}

/// The name Loci signs the articles it writes with.
enum LociAuthor {
  static let name = "Loci"

  static func wrote(_ item: Item) -> Bool {
    item.authors == [name]
  }
}

/// What an item is and where it comes from, under its title: `视频 · YouTube · 34:12`.
struct SavedItemByline: Equatable {
  enum Source: Equatable {
    /// Loci wrote it.
    case loci
    case named(String)
  }

  let kind: ItemKind
  let source: Source?
  let duration: Duration?

  init(_ item: Item) {
    kind = ItemKind(item.kind)
    if LociAuthor.wrote(item) {
      source = .loci
    } else if let name = item.site ?? item.authors.first ?? item.source?.host() {
      source = .named(name)
    } else {
      source = nil
    }
    switch item.kind {
    case .video(let length), .audio(let length): duration = length
    case .article, .paper, .repository: duration = nil
    }
  }

  var text: Text {
    var parts = [Text(Self.name(of: kind))]
    switch source {
    case .loci: parts.append(Text(.loci("added.byLoci")))
    case .named(let name): parts.append(Text(verbatim: name))
    case nil: break
    }
    if let duration { parts.append(Text(verbatim: MediaTime.text(duration)).monospacedDigit()) }
    return parts.dropFirst().reduce(parts[0]) { whole, next in Text(joining: whole, Text(verbatim: " · "), next) }
  }

  static func name(of kind: ItemKind) -> LocalizedStringResource {
    switch kind {
    case .article: .loci("added.article")
    case .paper: .loci("added.paper")
    case .video: .loci("added.video")
    case .audio: .loci("added.audio")
    case .repository: .loci("added.repository")
    }
  }
}
