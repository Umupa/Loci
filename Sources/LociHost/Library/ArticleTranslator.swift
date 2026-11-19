import Foundation
import LociMedia
import LociModel
import LociStore

/// Translates articles into the reader's language when asked. Passages go to the agent a batch at a time and
/// each batch is saved as it comes back, so the reader shows the start of the article while the rest is still
/// being translated. Passages translated before are kept and not sent again.
actor ArticleTranslator {
  static let batchSize = 20

  private let context: LibraryContext
  private let gate: Gate
  private var progress: [EntityID: TranslationProgress] = [:]
  private var work: [EntityID: Task<Void, Never>] = [:]

  init(context: LibraryContext, gate: Gate) {
    self.context = context
    self.gate = gate
  }

  func progress(of item: EntityID) -> TranslationProgress? {
    progress[item]
  }

  /// Starts translating `item` unless it is already being translated.
  func start(_ item: EntityID) {
    guard work[item] == nil else { return }
    progress[item] = .running(Fraction(0))
    work[item] = Task { await self.translate(item) }
  }

  /// Stops every translation under way; what was saved stays.
  func close() async {
    let running = Array(work.values)
    for task in running { task.cancel() }
    for task in running { await task.value }
  }

  private func translate(_ item: EntityID) async {
    do throws(HostError) {
      try await run(item)
      progress[item] = nil
    } catch {
      progress[item] = Task.isCancelled ? nil : .failed(String(describing: error))
    }
    work[item] = nil
    await context.notify([.item(item)])
  }

  private func run(_ item: EntityID) async throws(HostError) {
    let store = context.store
    let language = context.targetLanguage
    let (found, text, before) = try attempt {
      (
        try store.item(item), try store.fetchedContent(of: item),
        try store.articleTranslation(of: item, into: language)
      )
    }
    guard let text else { throw .notFound("the text of \(item)") }
    guard let make = context.media.transcriptAgent else {
      throw .invalidRequest("No agent is available to translate on this Mac.")
    }
    let agent = make(context.runtime)
    let passages = ArticlePassages.of(text, title: found.title)
    var translated = before?.bySource ?? [:]
    let missing = passages.filter { translated[$0] == nil }
    for start in stride(from: 0, to: missing.count, by: Self.batchSize) {
      if Task.isCancelled { return }
      let batch = Array(missing[start..<min(start + Self.batchSize, missing.count)])
      let lines = try await gate.through { () async throws(HostError) -> [String] in
        try await agent.translate(passages: batch, into: language)
      }
      for (source, line) in zip(batch, lines) { translated[source] = line }
      let translation = try attempt {
        try ArticleTranslation(
          language: language,
          passages: passages.compactMap { source in translated[source].map { .init(source: source, text: $0) } })
      }
      try attempt { try store.save(translation, of: item) }
      let done = passages.count { translated[$0] != nil }
      progress[item] = .running(Fraction(Double(done) / Double(max(passages.count, 1))))
      await context.notify([.item(item)])
    }
  }
}
