import Foundation
import LociMedia
import LociModel
import Synchronization

/// Sources that give what the test sets, read pages and connectors through the host as asked, and can be
/// held mid-fetch.
final class FakeSources: DataSourceRunning {
  private struct State {
    var records: [String: SourceRecord]
    var entries: [SourceEntry] = []
    var failure: SourceFailure?
    var asks: [SourceRequest] = []
    var fetches = 0
    var finished = 0
    var names: [String] = []
    var replayed: [String] = []
    var read: [String] = []
    var held = false
    /// Only fetches of this script are held, when set.
    var heldScript: String?
    var replayFailure: SourceProblems?
    var replaysHeld = false
    var replaying = 0
    var waiting: [CheckedContinuation<Void, Never>] = []
  }

  private let state: Mutex<State>

  init(records: [String: SourceRecord] = [:], failure: SourceProblems? = nil) {
    state = Mutex(State(records: records, failure: failure.map(SourceFailure.unreachable)))
  }

  var fetches: Int { state.withLock { $0.fetches } }
  /// Fetches that got past any hold.
  var finished: Int { state.withLock { $0.finished } }
  /// The name of each source fetched, in order.
  var names: [String] { state.withLock { $0.names } }
  var replayed: [String] { state.withLock { $0.replayed } }
  /// Replays waiting on `release`.
  var replaying: Int { state.withLock { $0.replaying } }
  /// What the host read for the pages and connectors asked for.
  var read: [String] { state.withLock { $0.read } }

  func set(_ records: [String: SourceRecord]) {
    state.withLock { $0.records = records }
  }

  func set(entries: [SourceEntry]) {
    state.withLock { $0.entries = entries }
  }

  /// Every fetch fails so from now on, a script's failure with its sample taken at the fetch's time; `nil`
  /// makes them work again.
  func fail(_ failure: SourceFailure?) {
    state.withLock { $0.failure = failure }
  }

  /// Every replay fails so from now on; `nil` makes them work again.
  func failReplays(_ problems: SourceProblems?) {
    state.withLock { $0.replayFailure = problems }
  }

  /// What each fetch asks the host to read besides plain GETs.
  func ask(_ requests: [SourceRequest]) {
    state.withLock { $0.asks = requests }
  }

  /// Fetches wait from now on until `release`; only those of `script`, when given.
  func hold(script: String? = nil) {
    state.withLock {
      $0.held = true
      $0.heldScript = script
    }
  }

  /// Replays wait from now on until `release`.
  func holdReplays() {
    state.withLock { $0.replaysHeld = true }
  }

  func release() {
    let waiting = state.withLock { current in
      current.held = false
      current.replaysHeld = false
      current.replaying = 0
      defer { current.waiting = [] }
      return current.waiting
    }
    for fetch in waiting { fetch.resume() }
  }

  func fetch(_ source: DataSource, state given: JSONValue?, now: Timestamp, elsewhere: any SourceReading)
    async throws(SourceFailure) -> SourceResult
  {
    let asks = state.withLock { current in
      current.fetches += 1
      current.names.append(source.name)
      return current.asks
    }
    await withCheckedContinuation { continuation in
      let held = state.withLock { current in
        let holds = current.held && (current.heldScript.map { $0 == source.script } ?? true)
        if holds { current.waiting.append(continuation) }
        return holds
      }
      if !held { continuation.resume() }
    }
    var responses: [SourceResponse] = []
    for ask in asks {
      do throws(SourceProblems) {
        let text = try await elsewhere.read(ask)
        state.withLock { $0.read.append(text) }
        responses.append(SourceResponse(url: ask.address, status: 200, text: text))
      } catch {
        throw .unreachable(error)
      }
    }
    let (records, entries, failure) = state.withLock { ($0.records, $0.entries, $0.failure) }
    state.withLock { $0.finished += 1 }
    if case .script(let problems, let sample?) = failure {
      throw .script(
        problems, sample: SourceSample(at: now, state: given, requests: sample.requests, responses: sample.responses))
    }
    if let failure { throw failure }
    return SourceResult(
      records: records, entries: entries, state: nil,
      sample: SourceSample(at: now, state: given, requests: asks, responses: responses))
  }

  func replay(_ sample: SourceSample, script: String) async throws(SourceProblems) -> SourceResult {
    await withCheckedContinuation { continuation in
      let held = state.withLock { current in
        if current.replaysHeld {
          current.waiting.append(continuation)
          current.replaying += 1
        }
        return current.replaysHeld
      }
      if !held { continuation.resume() }
    }
    let (records, failure) = state.withLock { current in
      current.replayed.append(script)
      return (current.records, current.replayFailure)
    }
    if let failure { throw failure }
    return SourceResult(records: records, state: nil, sample: sample)
  }
}
