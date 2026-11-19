import Foundation
import LociModel

/// One agent command-line program. Opens sessions and holds no session state itself.
public protocol AgentDriver: Sendable {
  var provider: Provider { get }
  func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession
}

public struct SessionConfiguration: Hashable, Sendable {
  public var workingDirectory: URL
  /// The provider's own name for the model; `nil` leaves the choice to the provider.
  public var model: String?
  /// `nil` leaves it to the provider. Drivers whose provider offers no efforts ignore it.
  public var effort: ThinkingEffort?
  /// An earlier session to continue instead of starting a new one.
  public var resume: SessionHandle?
  /// Variables this session's program gets on top of the environment every program gets.
  public var environment: [String: String]

  /// Every session runs with full access: the agent does not stop to ask before using a tool.
  public init(
    workingDirectory: URL, model: String? = nil, effort: ThinkingEffort? = nil, resume: SessionHandle? = nil,
    environment: [String: String] = [:]
  ) {
    self.workingDirectory = workingDirectory
    self.model = model
    self.effort = effort
    self.resume = resume
    self.environment = environment
  }

  /// The whole environment of the session's program: `base`, or this process's own when it is `nil`, with
  /// the session's variables over it.
  func environment(over base: [String: String]?) -> [String: String]? {
    guard !environment.isEmpty else { return base }
    return (base ?? ProcessInfo.processInfo.environment).merging(environment) { $1 }
  }
}

/// What a provider needs to find a session again. Callers store it with the conversation and never look inside.
public struct SessionHandle: Hashable, Codable, Sendable {
  public let provider: Provider
  public let value: String

  public init(provider: Provider, value: String) {
    self.provider = provider
    self.value = value
  }
}
