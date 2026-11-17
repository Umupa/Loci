/// The agent and model a mentor runs on.
public struct AgentChoice: Hashable, Codable, Sendable {
  public let provider: Mentor.Provider
  /// `nil` leaves the choice to the provider.
  public let model: String?

  /// A blank model is no model.
  public init(provider: Mentor.Provider, model: String? = nil) {
    self.provider = provider
    let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.model = trimmed.isEmpty ? nil : trimmed
  }
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

/// The agent and model new mentors run on.
public struct NewMentorAgent: Command {
  public static let name = "agents.default"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> AgentChoice {
    try await handler.newMentorAgent()
  }
}

/// Changes the agent and model new mentors run on. Mentors that already exist keep theirs.
public struct SetNewMentorAgent: Command {
  public static let name = "agents.setDefault"
  public let choice: AgentChoice

  public init(_ choice: AgentChoice) {
    self.choice = choice
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> AgentChoice {
    try await handler.setNewMentorAgent(self)
  }
}

/// Changes what one mentor runs on and how much it may do without asking. The next turn starts a new
/// session with them; a turn already running finishes as it began.
public struct SetMentorAgent: Command {
  public static let name = "mentor.setAgent"
  public let mentor: EntityID
  public let choice: AgentChoice
  public let permission: Mentor.Permission

  public init(mentor: EntityID, choice: AgentChoice, permission: Mentor.Permission) {
    self.mentor = mentor
    self.choice = choice
    self.permission = permission
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Mentor {
    try await handler.setMentorAgent(self)
  }
}
