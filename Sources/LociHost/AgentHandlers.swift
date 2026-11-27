import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func detectAgents(again: Bool) async -> [AgentInstallation] {
    await agents.installations(again: again)
  }

  public func agentModels(of provider: Provider) async -> [AgentModel] {
    guard provider == .bundledPi else { return await agentModels.models(of: provider) }
    return await agents.models(of: .bundledPi)
  }

  /// Has every installed agent's models listed, the old lists asked for again, so the pickers have them at once.
  func warmAgentModels() async {
    for installation in await environment.detectAgents(false) {
      guard case .installed(let found) = installation, found.provider != .bundledPi else { continue }
      _ = await agentModels.models(of: found.provider)
    }
  }

  public func runtime(of conversation: ConversationRef) async throws(HostError) -> Runtime {
    await agents.selection(await agents.runtime(of: conversation)).runtime
  }

  public func runtimeInUse(of conversation: ConversationRef) async throws(HostError) -> RuntimeInUse {
    let kindDefault = await agents.selection(await agents.kindDefault(conversation.kind)).runtime
    guard let own = try? database.runtime(of: conversation) else {
      return RuntimeInUse(runtime: kindDefault, kindDefault: kindDefault, isOwn: false)
    }
    return RuntimeInUse(runtime: await agents.selection(own).runtime, kindDefault: kindDefault, isOwn: true)
  }

  /// The conversations whose item, course or project is gone are left out.
  public func runtimeDefaults() async throws(HostError) -> RuntimeDefaults {
    var kinds: [RuntimeDefaults.KindDefault] = []
    for kind in ConversationKind.allCases {
      kinds.append(.init(kind: kind, runtime: await agents.selection(await agents.kindDefault(kind)).runtime))
    }
    let chosen = (try? database.ownRuntimes()) ?? []
    let items = store.items(
      withIDs: Set(chosen.compactMap { if case .item(let id) = $0.conversation { id } else { nil } }))
    var own: [RuntimeDefaults.OwnRuntime] = []
    for (conversation, runtime) in chosen {
      let title: String? =
        switch conversation {
        case .main: nil
        case .item(let id): items[id]?.title
        case .course(let id): try? store.course(id).title
        case .project(let id): try? store.project(id).name
        }
      guard let title else { continue }
      own.append(.init(conversation: conversation, title: title, runtime: await agents.selection(runtime).runtime))
    }
    return RuntimeDefaults(kinds: kinds, own: own)
  }

  public func setRuntime(_ command: SetConversationRuntime) async throws(HostError) -> Runtime {
    try await agents.choose(command.runtime, for: command.conversation, at: environment.now())
    await provisionPiIfSelected(in: command.conversation, retry: false)
    await follow([.runtime])
    return try await runtime(of: command.conversation)
  }

  public func setDefaultRuntime(_ command: SetDefaultRuntime) async throws(HostError) -> Runtime {
    try agents.setDefault(command.runtime, for: command.kind)
    if command.runtime.provider == .bundledPi, environment.bundledPi != nil,
      (try? await library.context.models.piCredential(for: command.runtime))?.key != nil
    {
      await hub.hold(Task { await self.installComponent(.bundledPi, retry: false) })
    }
    await follow([.runtime])
    return command.runtime
  }

  /// Whether the main conversation runs on the bundled Pi with no model or no Pi to run it yet.
  public func needsModelSetup() async -> Bool {
    guard environment.bundledPi != nil, await agents.runtime(of: .main).provider == .bundledPi else {
      return false
    }
    let credential = try? await library.context.models.piCredential(for: agents.provisionalRuntime(of: .main))
    return credential?.key == nil || library.context.equipment.support.activePi() == nil
  }

  /// Downloads the bundled Pi when the conversation runs on it and there is a model with a key for it.
  func provisionPiIfSelected(in conversation: ConversationRef = .main, retry: Bool) async {
    guard !Task.isCancelled, environment.bundledPi != nil,
      let credential = try? await library.context.models.piCredential(
        for: agents.provisionalRuntime(of: conversation)),
      credential.key != nil
    else { return }
    await hub.hold(
      Task {
        guard !Task.isCancelled, await self.agents.runtime(of: conversation).provider == .bundledPi else { return }
        await self.installComponent(.bundledPi, retry: retry)
      })
  }

  public func dataLocation() async -> HostPath {
    HostPath(store.root)
  }
}
