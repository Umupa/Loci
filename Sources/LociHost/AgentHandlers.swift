import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func detectAgents(again: Bool) async -> [AgentInstallation] {
    await agents.installations(again: again)
  }

  public func agentModels(of provider: Provider) async -> [String] {
    await agents.models(of: provider)
  }

  public func runtime(of conversation: ConversationRef) async throws(HostError) -> Runtime {
    await agents.selection(await agents.runtime(of: conversation)).runtime
  }

  public func setRuntime(_ command: SetConversationRuntime) async throws(HostError) -> Runtime {
    try agents.choose(command.runtime, for: command.conversation)
    await provisionPiIfSelected(in: command.conversation, retry: false)
    await follow([.runtime])
    return try await runtime(of: command.conversation)
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
