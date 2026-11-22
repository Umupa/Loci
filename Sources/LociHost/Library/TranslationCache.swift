import LociModel
import LociStore

actor TranslationCache {
  private typealias Answers = [TranslationCacheKey: String]

  private enum Outcome: Sendable {
    case translated(Answers)
    case failed(HostError)
    case cancelled
  }

  private actor Flight {
    private var outcome: Outcome?
    private var waiters: [CheckedContinuation<Outcome, Never>] = []

    func result() async -> Outcome {
      if let outcome { return outcome }
      return await withCheckedContinuation { waiters.append($0) }
    }

    func finish(_ outcome: Outcome) {
      self.outcome = outcome
      for waiter in waiters { waiter.resume(returning: outcome) }
      waiters.removeAll()
    }
  }

  private let store: Store
  private var pending: [TranslationCacheKey: Flight] = [:]
  private var generation = 0

  init(store: Store) {
    self.store = store
  }

  func bytes() -> Int64 { store.translationCacheBytes() }

  func clear() throws(HostError) {
    try attempt { try store.clearTranslationCache() }
    generation += 1
    pending.removeAll()
  }

  func translate(
    _ source: [String], keyedBy identity: [String],
    ask: @Sendable ([String]) async throws(HostError) -> [String]
  ) async throws(HostError) -> [String] {
    let keys = source.map { TranslationCacheKey(identity + [$0]) }
    let pairs = Array(zip(keys, source))
    let count = Set(keys).count
    var answers: Answers = [:]
    while answers.count < count {
      guard !Task.isCancelled else { throw .invalidRequest("Translation was cancelled.") }
      let flight = Flight()
      var needed: [(TranslationCacheKey, String)] = []
      var waiting: [TranslationCacheKey: Flight] = [:]
      var seen: Set<TranslationCacheKey> = []
      for (key, text) in pairs where answers[key] == nil && seen.insert(key).inserted {
        if let cached = store.cachedTranslation(for: key) {
          answers[key] = cached
        } else if let existing = pending[key] {
          waiting[key] = existing
        } else {
          needed.append((key, text))
          pending[key] = flight
        }
      }
      if !needed.isEmpty {
        let generation = generation
        let outcome = await fetch(needed, generation: generation, ask: ask)
        if generation == self.generation {
          for (key, _) in needed { pending[key] = nil }
        }
        await flight.finish(outcome)
        switch outcome {
        case .translated(let found): answers.merge(found) { _, new in new }
        case .failed(let error): throw error
        case .cancelled: throw .invalidRequest("Translation was cancelled.")
        }
      }
      for (key, existing) in waiting {
        switch await existing.result() {
        case .translated(let found): answers[key] = found[key]
        case .failed(let error): throw error
        case .cancelled: continue
        }
      }
    }
    return keys.compactMap { answers[$0] }
  }

  private func fetch(
    _ needed: [(TranslationCacheKey, String)], generation: Int,
    ask: @Sendable ([String]) async throws(HostError) -> [String]
  ) async -> Outcome {
    do throws(HostError) {
      let lines = try await ask(needed.map { $0.1 })
      guard !Task.isCancelled else { return .cancelled }
      guard lines.count == needed.count else {
        throw .invalidRequest("The translation has \(lines.count) lines for \(needed.count) inputs.")
      }
      let answers = Dictionary(uniqueKeysWithValues: zip(needed.map { $0.0 }, lines))
      if generation == self.generation {
        try attempt { try store.cacheTranslations(answers) }
      }
      return .translated(answers)
    } catch {
      return Task.isCancelled ? .cancelled : .failed(error)
    }
  }
}
