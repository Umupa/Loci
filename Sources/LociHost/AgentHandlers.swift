import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func detectAgents(again: Bool) async -> [AgentInstallation] {
    await environment.detectAgents(again)
  }

  public func agentModels(of provider: Mentor.Provider) async -> [String] {
    await environment.models(provider)
  }

  /// What is chosen in `settings.json`, falling back to what the host was started with.
  public func agentDefaults() async throws(HostError) -> AgentDefaults {
    defaults(from: try attempt { try store.settings() })
  }

  public func setDefaultAgent(_ command: SetDefaultAgent) async throws(HostError) -> AgentDefaults {
    defaults(from: try attempt { try store.changeSettings { $0.agent = command.provider } })
  }

  public func setDefaultModel(_ command: SetDefaultModel) async throws(HostError) -> AgentDefaults {
    let model = AgentChoice(provider: command.provider, model: command.model).model
    return defaults(from: try attempt { try store.changeSettings { $0.models[command.provider] = model } })
  }

  public func setMentorAgent(_ command: SetMentorAgent) async throws(HostError) -> Mentor {
    let changed = try attempt {
      let mentor = try store.mentor(command.mentor)
      let changed = try Mentor(
        id: mentor.id, name: mentor.name, avatar: mentor.avatar, color: mentor.color,
        provider: command.choice.provider, model: command.choice.model, effort: command.choice.effort,
        request: mentor.request)
      try store.save(changed)
      return changed
    }
    await mentors.settingsChanged(changed)
    await follow([.mentor(changed.id)])
    return changed
  }

  public func lessonLanguage() async throws(HostError) -> LessonLanguage {
    try attempt { try store.settings() }.lessonLanguage
  }

  public func setLessonLanguage(_ command: SetLessonLanguage) async throws(HostError) -> LessonLanguage {
    try attempt { try store.changeSettings { $0.lessonLanguage = command.language } }.lessonLanguage
  }

  public func dataLocation() async -> URL {
    store.root
  }

  private func defaults(from settings: HostSettings) -> AgentDefaults {
    var models = settings.models
    let provider = settings.agent ?? environment.defaultProvider
    if settings.agent == nil, models[provider] == nil { models[provider] = environment.defaultModel }
    return AgentDefaults(provider: provider, models: models)
  }
}
