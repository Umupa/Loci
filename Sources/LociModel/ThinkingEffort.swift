/// How hard an agent thinks before it replies, from not at all to as hard as it can.
public enum ThinkingEffort: String, CaseIterable, Codable, Hashable, Sendable {
  case off, minimal, low, medium, high, xhigh, max
}

extension Mentor.Provider {
  /// The efforts the provider's program can be asked for, lowest first; empty when it cannot be asked.
  public var efforts: [ThinkingEffort] {
    switch self {
    case .claudeCode: [.low, .medium, .high, .xhigh, .max]
    case .codex: [.low, .medium, .high, .xhigh, .max]
    case .pi: [.off, .minimal, .low, .medium, .high, .xhigh, .max]
    case .omp, .grok, .antigravity, .cursor, .fx, .hermes, .opencode: []
    }
  }
}
