/// A model an agent offers.
public struct AgentModel: Hashable, Codable, Sendable {
  /// What the agent's sessions are opened with.
  public let id: String
  /// How the agent itself shows it.
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

/// The models a provider's program offers, in its own order; empty while it cannot list them. The host answers
/// from what it listed before and asks the program again in the background when that is old.
public struct AgentModelList: Subscription {
  public static let name = "agents.models"
  public let provider: Provider

  public init(_ provider: Provider) {
    self.provider = provider
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> [AgentModel] {
    await handler.agentModels(of: provider)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.agentModels) || changes.contains(.everything)
  }
}

/// Every kind's default and the conversations that chose their own, kept current.
public struct RuntimeOverview: Subscription {
  public static let name = "conversation.runtime.overview"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> RuntimeDefaults {
    try await handler.runtimeDefaults()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.runtime) || changes.contains(.projects) || changes.contains(.everything)
  }
}

/// What conversations run on: each kind's default, and the conversations that chose their own.
public struct RuntimeDefaults: Hashable, Codable, Sendable {
  /// One for every kind, in `ConversationKind.allCases` order.
  public let kinds: [KindDefault]
  /// Within a kind, the most recently chosen first.
  public let own: [OwnRuntime]

  public init(kinds: [KindDefault], own: [OwnRuntime]) {
    self.kinds = kinds
    self.own = own
  }

  public struct KindDefault: Hashable, Codable, Sendable {
    public let kind: ConversationKind
    public let runtime: Runtime

    public init(kind: ConversationKind, runtime: Runtime) {
      self.kind = kind
      self.runtime = runtime
    }
  }

  /// A conversation that runs on its own choice rather than its kind's default.
  public struct OwnRuntime: Hashable, Codable, Sendable {
    public let conversation: ConversationRef
    /// The item's, course's or project's title.
    public let title: String
    public let runtime: Runtime

    public init(conversation: ConversationRef, title: String, runtime: Runtime) {
      self.conversation = conversation
      self.title = title
      self.runtime = runtime
    }
  }
}
