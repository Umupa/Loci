import Foundation

/// What the probe found for one provider on the host's Mac.
public enum AgentInstallation: Hashable, Codable, Sendable {
  /// Nothing was found under the names this provider's installer uses.
  case missing(Provider)
  case installed(Installed)

  /// A program that was found, with what it said about itself.
  public struct Installed: Hashable, Codable, Sendable {
    public let provider: Provider
    public let executable: HostPath
    /// What the program printed for its version, trimmed; `nil` when it has no version flag, printed no
    /// version, or never answered.
    public let version: String?
    /// Whether the program holds credentials, as far as it can say before a session starts.
    public let signIn: SignIn

    public init(provider: Provider, executable: HostPath, version: String?, signIn: SignIn) {
      self.provider = provider
      self.executable = executable
      self.version = version
      self.signIn = signIn
    }
  }

  /// Whether a program holds credentials.
  public enum SignIn: Hashable, Codable, Sendable {
    case signedIn
    case signedOut
    /// The program cannot say without starting a session. Every CLI Loci drives is in this state: the
    /// previous version learned about a missing sign-in from a failed turn, never from a probe.
    case unknown
  }

  public var provider: Provider {
    switch self {
    case .missing(let provider): provider
    case .installed(let installed): installed.provider
    }
  }
}
