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
    var replayed: [String] = []
    var read: [String] = []
    var held = false
    var waiting: [CheckedContinuation<Void, Never>] = []
  }

  private let state: Mutex<State>

  init(records: [String: SourceRecord] = [:], failure: SourceProblems? = nil) {
    state = Mutex(State(records: records, failure: failure.map(SourceFailure.unreachable)))
  }

  var fetches: Int { state.withLock { $0.fetches } }
  var replayed: [String] { state.withLock { $0.replayed } }
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

  /// What each fetch asks the host to read besides plain GETs.
  func ask(_ requests: [SourceRequest]) {
    state.withLock { $0.asks = requests }
  }

  /// Fetches wait from now on until `release`.
  func hold() {
    state.withLock { $0.held = true }
  }

  func release() {
    let waiting = state.withLock { current in
      current.held = false
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
      return current.asks
    }
    await withCheckedContinuation { continuation in
      let held = state.withLock { current in
        if current.held { current.waiting.append(continuation) }
        return current.held
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
    let records = state.withLock { current in
      current.replayed.append(script)
      return current.records
    }
    return SourceResult(records: records, state: nil, sample: sample)
  }
}
