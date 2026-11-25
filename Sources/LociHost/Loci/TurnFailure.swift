import LociAgents
import LociModel

/// Why a turn could not run, as the conversation tells it.
struct TurnFailure: Error {
  let ending: TurnEnding

  init(_ ending: TurnEnding) {
    self.ending = ending
  }

  /// Opening the provider's agent failed: it would not start, or it started and then failed.
  init(starting provider: Provider, _ error: AgentError) {
    switch error {
    case .wouldNotStart: ending = .unstarted(provider, .wouldNotStart)
    case .cannotLaunch: ending = .unstarted(provider, .notInstalled)
    default: ending = .failed(error.explanation)
    }
  }

  static func from<Value>(_ body: () throws(HostError) -> Value) throws(TurnFailure) -> Value {
    do {
      return try body()
    } catch {
      throw TurnFailure(.failed(String(describing: error)))
    }
  }

  static func awaiting<Value>(_ body: () async throws(AgentError) -> Value) async throws(TurnFailure) -> Value {
    do {
      return try await body()
    } catch {
      throw TurnFailure(.failed(error.explanation))
    }
  }
}
