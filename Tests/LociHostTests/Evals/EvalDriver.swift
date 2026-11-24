import Foundation
import LociAgents
import LociModel
import Synchronization

/// What one session was asked first, the tokens its last turn reported, and how long its turns took.
struct EvalCost: Sendable, Codable, Equatable {
  var tokens: Int?
  var seconds: Double = 0
  var prompt: String?
}

/// Wraps the driver the host runs on and writes down, for each session, how many tokens it reported and how
/// long its turns took. It changes nothing the agent sees or says.
final class EvalDriver: AgentDriver, Sendable {
  private let inner: any AgentDriver
  private let costs = Mutex<[String: EvalCost]>([:])

  init(_ inner: any AgentDriver) {
    self.inner = inner
  }

  var provider: Provider { inner.provider }

  /// The cost of the session tagged `tag` (`run/<id>`), if one was opened.
  func cost(of tag: String) -> EvalCost? {
    costs.withLock { $0[tag] }
  }

  func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    let tag = configuration.environment[LocalCall.sessionVariable] ?? "untagged"
    let session = try await inner.open(configuration)
    return EvalSession(inner: session, record: { [self] change in self.note(tag, change) })
  }

  private func note(_ tag: String, _ change: (inout EvalCost) -> Void) {
    costs.withLock { change(&$0[tag, default: EvalCost()]) }
  }
}

private final class EvalSession: AgentSession, Sendable {
  private let inner: any AgentSession
  private let record: @Sendable (_ change: (inout EvalCost) -> Void) -> Void

  init(inner: any AgentSession, record: @escaping @Sendable (_ change: (inout EvalCost) -> Void) -> Void) {
    self.inner = inner
    self.record = record
  }

  var handle: SessionHandle { inner.handle }

  func send(_ text: String) async throws(AgentError) -> Turn {
    let started = ContinuousClock.now
    record { if $0.prompt == nil { $0.prompt = text } }
    let turn = try await inner.send(text)
    let (events, out) = AsyncStream.makeStream(of: AgentEvent.self)
    let record = self.record
    Task {
      for await event in turn.events {
        if case .context(let usage) = event, let used = usage.used { record { $0.tokens = used } }
        if case .ended = event {
          let elapsed = ContinuousClock.now - started
          record { $0.seconds += Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18 }
        }
        out.yield(event)
      }
      out.finish()
    }
    return Turn(events: events)
  }

  func interrupt() async { await inner.interrupt() }

  func answer(_ request: PermissionRequest.ID, with answer: PermissionAnswer) async {
    await inner.answer(request, with: answer)
  }

  func close() async { await inner.close() }
}
