import Foundation
import LociModel

/// One agent command-line program. Opens sessions and holds no session state itself.
public protocol AgentDriver: Sendable {
  var provider: Mentor.Provider { get }
  func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession
}

public struct SessionConfiguration: Hashable, Sendable {
  public var workingDirectory: URL
  /// The provider's own name for the model; `nil` leaves the choice to the provider.
  public var model: String?
  public var permission: Mentor.Permission
  /// An earlier session to continue instead of starting a new one.
  public var resume: SessionHandle?

  public init(
    workingDirectory: URL, model: String? = nil, permission: Mentor.Permission, resume: SessionHandle? = nil
  ) {
    self.workingDirectory = workingDirectory
    self.model = model
    self.permission = permission
    self.resume = resume
  }
}

/// What a provider needs to find a session again. Callers store it with the conversation and never look inside.
public struct SessionHandle: Hashable, Codable, Sendable {
  public let provider: Mentor.Provider
  public let value: String

  public init(provider: Mentor.Provider, value: String) {
    self.provider = provider
    self.value = value
  }
}
