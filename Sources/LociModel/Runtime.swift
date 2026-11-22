import Foundation

/// The agent command-line program Loci runs on.
public enum Provider: String, CaseIterable, Codable, CodingKeyRepresentable, Hashable, Sendable {
  case pi
  case bundledPi = "bundled-pi"
  case omp
  case grok
  case antigravity
  case cursor
  case fx
  case hermes
  case claudeCode = "claude-code"
  case codex
  case opencode

  /// The efforts the provider's program can be asked for, lowest first; empty when it cannot be asked.
  public var efforts: [ThinkingEffort] {
    switch self {
    case .claudeCode: [.low, .medium, .high, .xhigh, .max]
    case .codex: [.low, .medium, .high, .xhigh, .max]
    case .pi, .bundledPi: [.off, .minimal, .low, .medium, .high, .xhigh, .max]
    case .omp, .grok, .antigravity, .cursor, .fx, .hermes, .opencode: []
    }
  }
}

/// How hard an agent thinks before it replies, from not at all to as hard as it can.
public enum ThinkingEffort: String, CaseIterable, Codable, Hashable, Sendable {
  case off, minimal, low, medium, high, xhigh, max
}

/// What Loci runs on: one setting for the whole app. Soul and memory are files every runtime shares.
public struct Runtime: Hashable, Sendable {
  public let provider: Provider
  /// `nil` leaves the choice to the provider.
  public let model: String?
  /// `nil` leaves it to the provider. Always one of `provider.efforts`.
  public let effort: ThinkingEffort?

  /// A blank model is no model, and an effort the provider does not offer is none.
  public init(provider: Provider, model: String? = nil, effort: ThinkingEffort? = nil) {
    self.provider = provider
    let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.model = trimmed.isEmpty ? nil : trimmed
    self.effort = effort.flatMap { provider.efforts.contains($0) ? $0 : nil }
  }
}

extension Runtime: Codable {
  private enum CodingKeys: String, CodingKey {
    case provider, model, effort
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      provider: try container.decode(Provider.self, forKey: .provider),
      model: try container.decodeIfPresent(String.self, forKey: .model),
      effort: try container.decodeIfPresent(ThinkingEffort.self, forKey: .effort))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(provider, forKey: .provider)
    try container.encodeIfPresent(model, forKey: .model)
    try container.encodeIfPresent(effort, forKey: .effort)
  }
}

/// What Loci runs on now.
public struct ReadRuntime: Command {
  public static let name = "runtime.read"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> Runtime {
    try await handler.runtime()
  }
}

/// Changes what Loci runs on. Every conversation's next turn opens a new session on it; a turn already
/// running finishes as it began.
public struct SetRuntime: Command {
  public static let name = "runtime.set"
  public let runtime: Runtime

  public init(_ runtime: Runtime) {
    self.runtime = runtime
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Runtime {
    try await handler.setRuntime(self)
  }
}

/// What each provider is on the host's Mac, in `Provider.allCases` order. Looking takes a few seconds, so
/// the host remembers what it found until asked to look `again`.
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
  public let provider: Provider

  public init(provider: Provider) {
    self.provider = provider
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [String] {
    await handler.agentModels(of: provider)
  }
}

/// What Loci runs on, kept current.
public struct CurrentRuntime: Subscription {
  public static let name = "runtime"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> Runtime {
    try await handler.runtime()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.runtime) || changes.contains(.everything)
  }
}
