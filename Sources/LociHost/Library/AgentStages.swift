import Foundation
import LociMedia
import LociModel
import LociStore

/// The stages an agent does: translating the transcript and finding chapters and highlights.
extension JobRun {
  /// Translates into the reader's language, unless the transcript is in it already or a translation fits.
  func translate(_ item: Item) async throws(StageStop) {
    guard let transcript = try stored({ try context.store.transcript(of: item.id) }), !transcript.segments.isEmpty
    else { return }
    let target = context.targetLanguage
    if let spoken = transcript.language, Self.primary(spoken) == Self.primary(target) { return }
    let translations = try stored { try context.store.translations(of: item.id) }
    if translations.contains(where: { $0.language == target && $0.fits(transcript) }) { return }
    let agent = try agent()
    let translation = try await inTurn(queue.gates.agents, at: .translate) {
      () async throws(StageStop) -> Translation in
      do throws(HostError) {
        return try await agent.translate(transcript, into: target)
      } catch {
        throw .failed(Self.describe(error))
      }
    }
    guard translation.fits(transcript) else {
      throw .failed("the translation has \(translation.lines.count) lines for \(transcript.segments.count) sentences")
    }
    try stored { try context.store.save(translation, of: item.id) }
  }

  /// Asks for chapters and highlights. Chapters the site gave are kept; the agent adds the highlights.
  func outline(_ item: Item) async throws(StageStop) {
    guard let transcript = try stored({ try context.store.transcript(of: item.id) }), !transcript.segments.isEmpty
    else { return }
    let agent = try agent()
    let written = try await inTurn(queue.gates.agents, at: .outline) { () async throws(StageStop) -> Outline in
      do throws(HostError) {
        return try await agent.outline(transcript, title: item.title)
      } catch {
        throw .failed(Self.describe(error))
      }
    }
    let platform = try stored { try context.store.outline(of: item.id) }?.chapters ?? []
    let outline = try stored {
      try Outline(chapters: platform.isEmpty ? written.chapters : platform, highlights: written.highlights)
    }
    try stored { try context.store.save(outline, of: item.id) }
  }

  private func agent() throws(StageStop) -> any TranscriptAgent {
    guard let make = context.media.transcriptAgent else { throw .wait(.agent) }
    return make(context.runtime)
  }

  static func primary(_ tag: String) -> String {
    String(tag.split(separator: "-").first ?? "").lowercased()
  }

  private static func describe(_ error: HostError) -> String {
    switch error {
    case .notFound(let what): "not found: \(what)"
    case .invalidRequest(let reason), .storage(let reason): reason
    case .alreadyExists(let id): "already exists: \(id)"
    case .invalidFile(let problem): problem.reason
    case .offline: "the Mac is offline"
    }
  }
}

/// Fetching the text of articles and papers.
extension JobRun {
  func extract(_ item: Item) async throws(StageStop) {
    guard let source = item.source else { return }
    guard let fetcher = context.media.textFetching else {
      throw .failed("Fetching articles and papers is not available in this build.", nil)
    }
    let fetched: Item
    switch item.kind {
    case .paper:
      let paper = try await fetch(source) { () async throws(FetchError) in try await fetcher.paper(at: source) }
      try stored { try context.store.savePDF(paper.pdf, of: item.id) }
      fetched = try stored {
        try Item(
          id: item.id, kind: .paper, title: paper.title, authors: paper.authors, source: source,
          language: item.language, site: item.site, published: paper.published.map(Timestamp.init))
      }
    default:
      let article = try await fetch(source) { () async throws(FetchError) in try await fetcher.article(at: source) }
      let images = Dictionary(article.images.map { ($0.name, $0.data) }, uniquingKeysWith: { first, _ in first })
      try stored { try context.store.saveArticle(article.markdown, images: images, of: item.id) }
      fetched = try stored {
        try Item(
          id: item.id, kind: .article, title: article.title, authors: article.authors, source: source,
          language: article.language.flatMap(Self.tag), site: article.site,
          published: article.published.map(Timestamp.init))
      }
    }
    try stored { try context.store.retitle(fetched, from: item.title) }
  }

  private func fetch<Value>(_ source: URL, _ body: () async throws(FetchError) -> Value) async throws(StageStop)
    -> Value
  {
    do {
      return try await body()
    } catch {
      throw error.needsLogin ? .wait(.login(site: source.host() ?? source.absoluteString)) : .failed(error.reason)
    }
  }
}
