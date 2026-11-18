import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func detectAgents(again: Bool) async -> [AgentInstallation] {
    await environment.detectAgents(again)
  }

  public func agentModels(of provider: Provider) async -> [String] {
    await environment.models(provider)
  }

  /// What is chosen in `settings.json`, falling back to what the host was started with.
  public func runtime() async throws(HostError) -> Runtime {
    try attempt { try store.settings() }.runtime ?? environment.defaultRuntime
  }

  public func setRuntime(_ command: SetRuntime) async throws(HostError) -> Runtime {
    _ = try attempt { try store.changeSettings { $0.runtime = command.runtime } }
    await follow([.runtime])
    return command.runtime
  }

  public func dataLocation() async -> HostPath {
    HostPath(store.root)
  }
}
