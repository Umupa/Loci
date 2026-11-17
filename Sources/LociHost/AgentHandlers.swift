import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func detectAgents(again: Bool) async -> [AgentInstallation] {
    await environment.detectAgents(again)
  }

  /// What is chosen in `settings.json`, or what the host was started with when nothing is.
  public func newMentorAgent() async throws(HostError) -> AgentChoice {
    let chosen = try attempt { try store.newMentorAgent() }
    return chosen ?? AgentChoice(provider: environment.defaultProvider, model: environment.defaultModel)
  }

  public func setNewMentorAgent(_ command: SetNewMentorAgent) async throws(HostError) -> AgentChoice {
    try attempt { try store.save(newMentorAgent: command.choice) }
    return command.choice
  }

  public func setMentorAgent(_ command: SetMentorAgent) async throws(HostError) -> Mentor {
    let changed = try attempt {
      let mentor = try store.mentor(command.mentor)
      let changed = try Mentor(
        id: mentor.id, name: mentor.name, avatar: mentor.avatar, color: mentor.color,
        provider: command.choice.provider, model: command.choice.model, permission: command.permission,
        request: mentor.request)
      try store.save(changed)
      return changed
    }
    await follow([.mentor(changed.id)])
    return changed
  }
}
