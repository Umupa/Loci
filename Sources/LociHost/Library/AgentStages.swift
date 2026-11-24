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
    let work = try await writer(chosen?.runtime)
    let sentences = transcript.segments.map(\.text)
    let prompt = work.prompt(.transcript, language: target, source: sentences)
    let identity = TranslationCacheKey(work.identity + prompt.cacheIdentity + sentences).digest
    let partial = Self.partial(target)
    let lines: [String]
    if work.usesRuntime {
      lines = try await inTurn(queue.gates.agents, at: .translate) { () async throws(StageStop) in
        try await translate(sentences, using: prompt, work: work, partial: partial, identity: identity)
      }
    } else {
      lines = try await translate(sentences, using: prompt, work: work, partial: partial, identity: identity)
    }
    if Task.isCancelled { return }
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

  private struct PartialTranslation: Codable {
    let identity: String
    var lines: [String]
  }

  private func translate(
    _ sentences: [String], using prompt: TranslationPrompt, work: TranscriptWork, partial: String, identity: String
  ) async throws(StageStop) -> [String] {
    var lines = translatedSoFar(partial, of: sentences.count, identity: identity, work: work)
    await queue.progress(item, stage: .translate, Fraction(Double(lines.count) / Double(sentences.count)))
    let batches = Batches.pieces(of: Array(sentences.dropFirst(lines.count)), size: Self.translationBatch)
    let translate = { @Sendable (_: Int, batch: [String]) async throws(StageStop) -> [String] in
      do throws(HostError) {
        return try await work.translate(batch, using: prompt)
      } catch {
        throw .failed(Self.describe(error))
      }
    }
    try await Batches.run(batches, parallelism: work.parallelism, work: translate) { batch async throws(StageStop) in
      if Task.isCancelled { return }
      lines += batch
      try stored {
        let kept = try JSONEncoder().encode(PartialTranslation(identity: identity, lines: lines))
        _ = try context.store.saveWork(kept, named: partial, of: item)
      }
      await queue.progress(item, stage: .translate, Fraction(Double(lines.count) / Double(sentences.count)))
    }
    return lines
  }

  private func translatedSoFar(_ name: String, of count: Int, identity: String, work: TranscriptWork) -> [String] {
    guard let text = try? context.store.workText(named: name, of: item) else { return [] }
    let data = Data(text.utf8)
    let decoder = JSONDecoder()
    if let saved = try? decoder.decode(PartialTranslation.self, from: data) {
      return saved.identity == identity && saved.lines.count <= count ? saved.lines : []
    }
    if work.usesRuntime, !work.settings.smart,
      work.settings.transcriptPrompt == TranslationSettings.defaultTranscriptPrompt,
      let lines = try? decoder.decode([String].self, from: data), lines.count <= count
    {
      return lines
    }
    return []
  }

  /// Asks for chapters, unless the site gave them.
  func outline(_ item: Item) async throws(StageStop) {
    guard let transcript = try stored({ try context.store.transcript(of: item.id) }), !transcript.segments.isEmpty,
      try stored({ try context.store.outline(of: item.id) })?.chapters.isEmpty ?? true
    else { return }
    let work = try await writer(nil)
    let write = { () async throws(StageStop) -> Outline in
      do throws(HostError) {
        return try await work.agent.outline(transcript, title: item.title)
      } catch {
        throw .failed(Self.describe(error))
      }
    }
    let outline =
      if work.usesRuntime {
        try await inTurn(queue.gates.agents, at: .outline, write)
      } else {
        try await write()
      }
    if Task.isCancelled { return }
    try stored { try context.store.save(outline, of: item.id) }
  }

  func writer(_ runtime: Runtime?) async throws(StageStop) -> TranscriptWork {
    let work: TranscriptWork?
    do throws(HostError) {
      work = try await context.transcriptWork(runtime)
    } catch {
      throw .failed(Self.describe(error))
    }
    guard let work else { throw .wait(.agent) }
    return work
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
    case .olderMac: "the other Mac runs an older Loci"
    }
  }
}
