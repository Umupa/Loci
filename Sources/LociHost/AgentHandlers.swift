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

  /// What is chosen in `settings.json`, falling back to what the host was started with.
  public func runtime() async throws(HostError) -> Runtime {
    _ = try attempt { try store.settings() }
    return await agents.selection().runtime
  }

  public func setRuntime(_ command: SetRuntime) async throws(HostError) -> Runtime {
    _ = try attempt { try store.changeSettings { $0.runtime = command.runtime } }
    await provisionPiIfSelected(retry: false)
    await follow([.runtime])
    return await agents.selection().runtime
  }

  public func needsModelSetup() async -> Bool {
    guard environment.bundledPi != nil, await agents.chosen().provider == .bundledPi else {
      return false
    }
    let credential = try? await library.context.models.piCredential(for: agents.provisionalRuntime)
    return credential?.key == nil || library.context.equipment.support.activePi() == nil
  }

  func provisionPiIfSelected(retry: Bool) async {
    guard !Task.isCancelled, environment.bundledPi != nil,
      let credential = try? await library.context.models.piCredential(for: agents.provisionalRuntime),
      credential.key != nil
    else { return }
    await hub.hold(
      Task {
        guard !Task.isCancelled, await self.agents.chosen().provider == .bundledPi else { return }
        await self.installComponent(.bundledPi, retry: retry)
      })
  }

  public func dataLocation() async -> HostPath {
    HostPath(store.root)
  }
}
