import Foundation
import LociAgents
import LociModel
import LociStore

/// What a host takes from the outside world, so tests can choose it.
public struct HostEnvironment: Sendable {
  public let newID: @Sendable () -> EntityID
  public let now: @Sendable () -> Timestamp
  /// The agent new mentors run on until settings can change it.
  public let defaultProvider: Mentor.Provider
  /// The model new mentors ask their agent for; `nil` leaves the choice to the agent.
  public let defaultModel: String?
  /// How deleted mentors and items leave the disk.
  public let discard: Discard
  /// The driver for a provider's program, or `nil` when it cannot be run here.
  public let agents: @Sendable (Mentor.Provider) async -> (any AgentDriver)?

  public init(
    newID: @escaping @Sendable () -> EntityID, now: @escaping @Sendable () -> Timestamp,
    defaultProvider: Mentor.Provider, defaultModel: String? = nil, discard: Discard,
    agents: @escaping @Sendable (Mentor.Provider) async -> (any AgentDriver)?
  ) {
    self.newID = newID
    self.now = now
    self.defaultProvider = defaultProvider
    self.defaultModel = defaultModel
    self.discard = discard
    self.agents = agents
  }

  /// The real clock, fresh identifiers, the Trash, and the agent programs installed on this Mac.
  public static func system(defaultProvider: Mentor.Provider, defaultModel: String? = nil) -> HostEnvironment {
    let installed = InstalledAgents()
    return HostEnvironment(
      newID: { EntityID() }, now: { Timestamp(.now) }, defaultProvider: defaultProvider, defaultModel: defaultModel,
      discard: .toTrash, agents: { await installed.driver(for: $0) })
  }
}

/// Looks for the agent programs the first time one is needed, which takes a moment: the login shell is asked
/// for its PATH.
actor InstalledAgents {
  private var programs: Task<AgentPrograms, Never>?

  func driver(for provider: Mentor.Provider) async -> (any AgentDriver)? {
    let programs = self.programs ?? Task { AgentPrograms(search: await AgentSearch.forThisMac()) }
    self.programs = programs
    return await programs.value.driver(for: provider)
  }
}
