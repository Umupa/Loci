import Foundation
import LociMedia
import LociModel
import LociStore

/// The stages an agent does: translating the transcript and finding chapters.
extension JobRun {
  /// How many sentences go to the agent at once; each batch is kept as it comes back.
  static let translationBatch = 60

  /// Translates into the language chosen when the item was taken in, or the reader's, on the runtime chosen
  /// for it; unless the transcript is in that language already or a translation fits. Batches are kept in the
  /// work folder as they come back and reported as a share, so a paused or quit translation carries on from the
  /// first sentence not yet translated.
  func translate(_ item: Item) async throws(StageStop) {
    guard let transcript = try stored({ try context.store.transcript(of: item.id) }), !transcript.segments.isEmpty
    else { return }
    let chosen = context.choice(of: item.id)?.translation
    let target = chosen?.language ?? context.targetLanguage
    if let spoken = transcript.language, Self.primary(spoken) == Self.primary(target) { return }
    let translations = try stored { try context.store.translations(of: item.id) }
    if translations.contains(where: { $0.language == target && $0.fits(transcript) }) { return }
    let agent = try agent(chosen?.runtime)
    let sentences = transcript.segments.map(\.text)
    let partial = Self.partial(target)
    let lines = try await inTurn(queue.gates.agents, at: .translate) { () async throws(StageStop) -> [String] in
      var lines = translatedSoFar(partial, of: sentences.count)
      let report = progress(.translate)
      report(Fraction(Double(lines.count) / Double(sentences.count)))
      while lines.count < sentences.count {
        let batch = Array(sentences[lines.count..<min(lines.count + Self.translationBatch, sentences.count)])
        do throws(HostError) {
          lines += try await agent.translate(lines: batch, into: target)
        } catch {
          throw .failed(Self.describe(error))
        }
        if let kept = try? JSONEncoder().encode(lines) {
          _ = try? context.store.saveWork(kept, named: partial, of: item.id)
        }
        report(Fraction(Double(lines.count) / Double(sentences.count)))
      }
      return lines
    }
    let translation = try stored { try Translation(language: target, lines: lines) }
    guard translation.fits(transcript) else {
      throw .failed("the translation has \(translation.lines.count) lines for \(transcript.segments.count) sentences")
    }
    try stored { try context.store.save(translation, of: item.id) }
    try? context.store.removeWork(named: partial, of: item.id)
  }

  /// Where the batches translated so far are kept.
  static func partial(_ language: String) -> String {
    "translating-\(language).json"
  }

  /// The lines a translation left part way holds; none when there is no such file or it does not fit.
  private func translatedSoFar(_ name: String, of count: Int) -> [String] {
    guard let text = try? context.store.workText(named: name, of: item),
      let lines = try? JSONDecoder().decode([String].self, from: Data(text.utf8)), lines.count <= count
    else { return [] }
    return lines
  }

  /// Asks for chapters, unless the site gave them.
  func outline(_ item: Item) async throws(StageStop) {
    guard let transcript = try stored({ try context.store.transcript(of: item.id) }), !transcript.segments.isEmpty,
      try stored({ try context.store.outline(of: item.id) })?.chapters.isEmpty ?? true
    else { return }
    let agent = try agent(nil)
    let outline = try await inTurn(queue.gates.agents, at: .outline) { () async throws(StageStop) -> Outline in
      do throws(HostError) {
        return try await agent.outline(transcript, title: item.title)
      } catch {
        throw .failed(Self.describe(error))
      }
    }
    try stored { try context.store.save(outline, of: item.id) }
  }

  /// The agent on `runtime`; `nil` follows what Loci runs on.
  func agent(_ runtime: Runtime?) throws(StageStop) -> any TranscriptAgent {
    guard let agent = context.transcriptAgent(runtime) else { throw .wait(.agent) }
    return agent
  }

  static func primary(_ tag: String) -> String {
    String(tag.split(separator: "-").first ?? "").lowercased()
  }

  static func describe(_ error: HostError) -> String {
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
  static let articleHTML = "article.html"

  func extract(_ item: Item) async throws(StageStop) {
    guard let source = item.source else { return }
    let html =
      item.kind == .article ? try stored { try context.store.workText(named: Self.articleHTML, of: item.id) } : nil
    if html == nil, try await recognize(item) { return }
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
          language: item.language, site: item.site, published: paper.published.map(Timestamp.init), why: item.why)
      }
    default:
      let article = try await fetch(source) { () async throws(FetchError) in
        try await fetcher.article(at: source, html: html)
      }
      let images = Dictionary(article.images.map { ($0.name, $0.data) }, uniquingKeysWith: { first, _ in first })
      try stored { try context.store.saveArticle(article.markdown, images: images, of: item.id) }
      fetched = try stored {
        try Item(
          id: item.id, kind: .article, title: article.title, authors: article.authors, source: source,
          language: article.language.flatMap(Self.tag), site: article.site,
          published: article.published.map(Timestamp.init), why: item.why)
      }
    }
    try stored {
      try context.store.retitle(fetched, from: item.title)
      if html != nil { try context.store.clearWork(of: item.id) }
    }
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
