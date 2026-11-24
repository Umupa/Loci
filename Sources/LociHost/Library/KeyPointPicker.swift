import Foundation
import LociMedia
import LociModel
import LociStore

/// Picks an item's key points when the reader asks, one item at a time per request, with a model service.
/// The key points picked before stay until the new ones are saved; a failure is kept to show until asked again.
actor KeyPointPicker {
  private let context: LibraryContext
  private var picking: [EntityID: KeyPointPicking] = [:]
  private var work: [EntityID: Task<Void, Never>] = [:]

  init(context: LibraryContext) {
    self.context = context
  }

  func picking(_ item: EntityID) -> KeyPointPicking? {
    picking[item]
  }

  /// Starts picking `item`'s key points with `choice`, unless they are being picked already.
  func start(_ item: EntityID, choice: KeyPointChoice) {
    guard work[item] == nil else { return }
    picking[item] = .running
    work[item] = Task { await self.pick(item, choice: choice) }
  }

  func close() async {
    let running = Array(work.values)
    for task in running { task.cancel() }
    for task in running { await task.value }
  }

  private func pick(_ item: EntityID, choice: KeyPointChoice) async {
    await context.notify([.item(item)])
    do throws(HostError) {
      try await run(item, choice: choice)
      picking[item] = nil
    } catch {
      picking[item] = Task.isCancelled ? nil : .failed(JobRun.describe(error))
    }
    work[item] = nil
    await context.notify([.item(item)])
  }

  private func run(_ item: EntityID, choice: KeyPointChoice) async throws(HostError) {
    let store = context.store
    let found = try attempt { try store.item(item) }
    let source = try attempt { try Self.source(of: found, in: store) }
    guard let work = try await context.modelWork(preferring: choice.model, for: .transcripts) else {
      throw .invalidRequest("No model service is configured to pick key points.")
    }
    let reader = KeyPointReader(
      language: context.media.readerLanguage, profile: (try? store.agentText(.profile)) ?? "", why: found.why)
    let points = try await work.agent.keyPoints(of: source, count: choice.count, for: reader)
    if Task.isCancelled { return }
    try attempt { try store.save(try KeyPoints(points: points, choice: choice), of: item) }
  }

  private static func source(of item: Item, in store: Store) throws -> KeyPointSource {
    switch item.kind {
    case .video, .audio:
      guard let transcript = try store.transcript(of: item.id), !transcript.segments.isEmpty else {
        throw HostError.invalidRequest("\(item.title) has no transcript yet")
      }
      return .transcript(transcript, title: item.title)
    case .article:
      guard let text = try store.fetchedContent(of: item.id) else {
        throw HostError.invalidRequest("\(item.title) has no text yet")
      }
      return .article(passages: ArticlePassages.of(text, title: item.title), title: item.title)
    case .paper, .repository:
      throw HostError.invalidRequest("Key points are picked for videos, audio and articles")
    }
  }
}
