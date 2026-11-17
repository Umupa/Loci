import Foundation
import LociAgents
import LociModel
import LociStore

/// What a host takes from the outside world, so tests can choose it.
public struct HostEnvironment: Sendable {
  public let newID: @Sendable () -> EntityID
  public let now: @Sendable () -> Timestamp
  /// The agent new mentors run on until one is chosen in the settings.
  public let defaultProvider: Mentor.Provider
  /// The model new mentors ask their agent for until one is chosen; `nil` leaves the choice to the agent.
  public let defaultModel: String?
  /// How deleted mentors and items leave the disk.
  public let discard: Discard
  /// The driver for a provider's program, or `nil` when it cannot be run here.
  public let agents: @Sendable (Mentor.Provider) async -> (any AgentDriver)?
  /// What each provider is on this Mac. `again` looks afresh, so a program installed since is found and
  /// can be driven; otherwise what was found last may be given.
  public let detectAgents: @Sendable (_ again: Bool) async -> [AgentInstallation]

  public init(
    newID: @escaping @Sendable () -> EntityID, now: @escaping @Sendable () -> Timestamp,
    defaultProvider: Mentor.Provider, defaultModel: String? = nil, discard: Discard,
    agents: @escaping @Sendable (Mentor.Provider) async -> (any AgentDriver)?,
    detectAgents: @escaping @Sendable (_ again: Bool) async -> [AgentInstallation] = { _ in [] }
  ) {
    self.newID = newID
    self.now = now
    self.defaultProvider = defaultProvider
    self.defaultModel = defaultModel
    self.discard = discard
    self.agents = agents
    self.detectAgents = detectAgents
  }

  /// The real clock, fresh identifiers, the Trash, and the agent programs installed on this Mac.
  public static func system(defaultProvider: Mentor.Provider, defaultModel: String? = nil) -> HostEnvironment {
    let installed = InstalledAgents()
    return HostEnvironment(
      newID: { EntityID() }, now: { Timestamp(.now) }, defaultProvider: defaultProvider, defaultModel: defaultModel,
      discard: .toTrash, agents: { await installed.driver(for: $0) },
      detectAgents: { await installed.detect(again: $0) })
  }
}

/// Looks for the agent programs the first time one is needed, which takes a moment: the login shell is asked
/// for its PATH. Looking again replaces what was found, so the drivers see a program installed since.
actor InstalledAgents {
  private var search: Task<AgentSearch, Never>?
  private var found: [AgentInstallation]?

  func driver(for provider: Mentor.Provider) async -> (any AgentDriver)? {
    AgentPrograms(search: await currentSearch()).driver(for: provider)
  }

  func detect(again: Bool) async -> [AgentInstallation] {
    if !again, let found { return found }
    if again { search = nil }
    let probe = AgentProbe(search: await currentSearch())
    let installations = await probe.installations()
    found = installations
    return installations
  }

  private func currentSearch() async -> AgentSearch {
    let search = self.search ?? Task { await AgentSearch.forThisMac() }
    self.search = search
    return await search.value
  }
}
