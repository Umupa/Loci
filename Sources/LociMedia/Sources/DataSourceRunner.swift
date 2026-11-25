import Foundation
import LociModel

/// Runs sources: what the host asks to fetch one, or to run a script on a sample again.
public protocol DataSourceRunning: Sendable {
  /// `requests(state)`, the GETs it asked for, then `parse(responses, now)`.
  func fetch(_ source: DataSource, state: JSONValue?, now: Timestamp) async throws(SourceProblems) -> SourceResult
  /// `parse` on what a sample got, without the network.
  func replay(_ sample: SourceSample, script: String) async throws(SourceProblems) -> SourceResult
}

/// Fetches over the network as no one, and runs each script call in its own `ParseSandbox`.
public struct DataSourceRunner: DataSourceRunning {
  let fetcher: SourceFetcher
  /// How long one call of a script may run.
  let timeout: Duration

  public init(network: any Network, timeout: Duration = .seconds(3)) {
    fetcher = SourceFetcher(network: network)
    self.timeout = timeout
  }

  public func fetch(_ source: DataSource, state: JSONValue?, now: Timestamp) async throws(SourceProblems)
    -> SourceResult
  {
    let asked = try await ParseSandbox.run(source.script, .requests(state: state), now: now, timeout: timeout)
    let requests = try DataSourceCheck.requests(from: asked)
    let responses = try await fetcher.fetch(requests)
    return try await replay(
      SourceSample(at: now, state: state, requests: requests, responses: responses), script: source.script)
  }

  public func replay(_ sample: SourceSample, script: String) async throws(SourceProblems) -> SourceResult {
    let parsed = try await ParseSandbox.run(
      script, .parse(responses: sample.responses), now: sample.at, timeout: timeout)
    let output = try DataSourceCheck.output(from: parsed)
    return SourceResult(records: output.records, state: output.state, sample: sample)
  }
}
