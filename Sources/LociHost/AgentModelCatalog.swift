import LociModel
import LociStore

/// The models each agent program offers, answered from what it listed last so a picker never waits once it has
/// listed them. A list older than `freshFor`, or made by another version of the program, is asked for again in
/// the background, and subscribers hear when it changed. A program that lists nothing keeps its last list.
actor AgentModelCatalog {
  static let freshFor: Int64 = 6 * 60 * 60 * 1000

  private let database: StoreDatabase
  private let list: @Sendable (Provider) async -> [AgentModel]
  private let version: @Sendable (Provider) async -> String?
  private let now: @Sendable () -> Timestamp
  private let changed: @Sendable () async -> Void
  private var asking: [Provider: Task<[AgentModel], Never>] = [:]

  init(
    database: StoreDatabase, list: @escaping @Sendable (Provider) async -> [AgentModel],
    version: @escaping @Sendable (Provider) async -> String?, now: @escaping @Sendable () -> Timestamp,
    changed: @escaping @Sendable () async -> Void
  ) {
    self.database = database
    self.list = list
    self.version = version
    self.now = now
    self.changed = changed
  }

  func models(of provider: Provider) async -> [AgentModel] {
    let version = await version(provider)
    guard let kept = try? database.listedModels(of: provider), !kept.models.isEmpty else {
      return await ask(provider, version: version)
    }
    if kept.version != version || now().millisecondsSince1970 - kept.listed.millisecondsSince1970 > Self.freshFor {
      Task { _ = await self.ask(provider, version: version) }
    }
    return kept.models
  }

  /// Lists the models of each provider again now, so the pickers have them before they are opened.
  func refresh(_ providers: [Provider]) async {
    for provider in providers {
      _ = await ask(provider, version: await version(provider))
    }
  }

  /// One question at a time per provider; whoever asks meanwhile gets the same answer.
  private func ask(_ provider: Provider, version: String?) async -> [AgentModel] {
    if let asked = asking[provider] { return await asked.value }
    let task = Task { await list(provider) }
    asking[provider] = task
    let models = await task.value
    asking[provider] = nil
    guard !models.isEmpty else { return (try? database.listedModels(of: provider))?.models ?? [] }
    let before = try? database.listedModels(of: provider)
    try? database.keepListedModels(.init(models: models, version: version, listed: now()), of: provider)
    if before?.models != models { await changed() }
    return models
  }
}
