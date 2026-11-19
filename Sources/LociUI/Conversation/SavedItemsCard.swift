import LociModel
import SwiftUI

/// Items Loci put into the library one after another, in one card: each with its cover, title, where it
/// comes from, and its work while that goes on. A row opens its item and can take it back out of the library.
/// Items deleted since show as faint lines under the card.
struct SavedItemsCard: View {
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
        VStack(spacing: 0) {
          ForEach(Array(shown.enumerated()), id: \.element.0.id) { index, line in
            SavedItemRow(item: line.0, work: line.1, divided: index > 0)
          }
        }
        .background(RoundedRectangle(cornerRadius: Radius.group, style: .continuous).fill(Palette.surface))
        .overlay {
          RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
            .strokeBorder(Palette.line, lineWidth: Size.hairline)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
      }
      ForEach(Array(deleted.enumerated()), id: \.offset) { _, line in
        if case .deleted(let title) = line { DeletedItemLine(title: title) }
      }
    }
    .frame(maxWidth: 420, alignment: .leading)
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
