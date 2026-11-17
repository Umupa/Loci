/// The agent, model and thinking effort a mentor runs on.
public struct AgentChoice: Hashable, Codable, Sendable {
  public let provider: Mentor.Provider
  /// `nil` leaves the choice to the provider.
  public let model: String?
  /// `nil` leaves it to the provider. Always one of `provider.efforts`.
  public let effort: ThinkingEffort?

  /// A blank model is no model, and an effort the provider does not offer is none.
  public init(provider: Mentor.Provider, model: String? = nil, effort: ThinkingEffort? = nil) {
    self.provider = provider
    let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.model = trimmed.isEmpty ? nil : trimmed
    self.effort = effort.flatMap { provider.efforts.contains($0) ? $0 : nil }
  }
}

/// What new mentors run on: one agent, and the model each agent is asked for.
public struct AgentDefaults: Hashable, Codable, Sendable {
  public let provider: Mentor.Provider
  /// Agents with no model here leave the choice to the agent.
  public let models: [Mentor.Provider: String]

  public init(provider: Mentor.Provider, models: [Mentor.Provider: String] = [:]) {
    self.provider = provider
    self.models = models.compactMapValues { model in
      let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
  }

  /// What a mentor made now runs on.
  public var forNewMentors: AgentChoice { AgentChoice(provider: provider, model: models[provider]) }
}

/// What each provider is on the host's Mac, in `Mentor.Provider.allCases` order. Looking takes a few
/// seconds, so the host remembers what it found until asked to look `again`.
public struct DetectAgents: Command {
  public static let name = "agents.detect"
  public let again: Bool

  public init(again: Bool = false) {
    self.again = again
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [AgentInstallation] {
    await handler.detectAgents(again: again)
  }
}

/// The models a provider's program offers, as it names them; empty when it cannot list them. Asked once
/// and then remembered.
public struct AgentModels: Command {
  public static let name = "agents.models"
  public let provider: Mentor.Provider

  public init(provider: Mentor.Provider) {
    self.provider = provider
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [String] {
    await handler.agentModels(of: provider)
  }
}

public struct ReadAgentDefaults: Command {
  public static let name = "agents.defaults"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> AgentDefaults {
    try await handler.agentDefaults()
  }
}

/// Changes the agent new mentors run on. Mentors that already exist keep theirs.
public struct SetDefaultAgent: Command {
  public static let name = "agents.setDefault"
  public let provider: Mentor.Provider

  public init(_ provider: Mentor.Provider) {
    self.provider = provider
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> AgentDefaults {
    try await handler.setDefaultAgent(self)
  }
}

/// Changes the model new mentors ask one agent for; `nil` leaves the choice to the agent.
public struct SetDefaultModel: Command {
  public static let name = "agents.setDefaultModel"
  public let provider: Mentor.Provider
  public let model: String?

  public init(provider: Mentor.Provider, model: String?) {
    self.provider = provider
    self.model = model
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> AgentDefaults {
    try await handler.setDefaultModel(self)
  }
}

/// Changes what one mentor runs on. The next turn starts a new session with it; a turn already running
/// finishes as it began.
public struct SetMentorAgent: Command {
  public static let name = "mentor.setAgent"
  public let mentor: EntityID
  public let choice: AgentChoice

  public init(mentor: EntityID, choice: AgentChoice) {
    self.mentor = mentor
    self.choice = choice
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Mentor {
    try await handler.setMentorAgent(self)
  }
}
