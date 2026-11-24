import LociMedia
import LociModel
import LociStore

extension JobRun {
  private static let articleBatch = 20

  func translateArticle(_ found: Item) async throws(StageStop) {
    guard let choice = context.choice(of: item)?.translation else { return }
    let language = choice.language
    if let original = found.language, Self.primary(original) == Self.primary(language) { return }
    let store = context.store
    let (text, before) = try stored {
      (try store.fetchedContent(of: item), try store.articleTranslation(of: item, into: language))
    }
    guard let text else { throw .failed("The article has no text to translate.") }
    let passages = ArticlePassages.of(text, title: found.title)
    var translated = before?.bySource ?? [:]
    var seen = Set(translated.keys)
    let missing = passages.filter { seen.insert($0).inserted }
    guard !missing.isEmpty else { return }

    let work = try await writer(choice.model, for: .translation)
    let prompt = work.prompt(.article, language: language, source: [found.title, text])
    let translate = { @Sendable (_: Int, batch: [String]) async throws(StageStop) -> [(String, String)] in
      let lines: [String]
      do throws(HostError) {
        lines = try await work.translate(batch, using: prompt)
      } catch {
        throw .failed(Self.describe(error))
      }
      return Array(zip(batch, lines))
    }

    let batches = Batches.pieces(of: missing, size: Self.articleBatch)
    try await Batches.run(batches, parallelism: work.parallelism, work: translate) { batch async throws(StageStop) in
      if Task.isCancelled { return }
      for (source, line) in batch { translated[source] = line }
      try stored {
        let translation = try ArticleTranslation(
          language: language,
          passages: passages.compactMap { source in translated[source].map { .init(source: source, text: $0) } })
        try store.save(translation, of: item)
      }
      let done = passages.count { translated[$0] != nil }
      await queue.progress(item, stage: .translate, Fraction(Double(done) / Double(passages.count)))
      await context.notify([.item(item)])
    }
  }
}
