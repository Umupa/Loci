import Foundation
import LociModel

/// Runs sources: what the host asks to fetch one, or to run a script on a sample again.
public protocol DataSourceRunning: Sendable {
  /// `requests(state)`, what it asked for, then `parse(responses, now)`; pages and connectors are read
  /// through `elsewhere`.
  func fetch(_ source: DataSource, state: JSONValue?, now: Timestamp, elsewhere: any SourceReading)
    async throws(SourceFailure) -> SourceResult
  /// `parse` on what a sample got, without the network.
  func replay(_ sample: SourceSample, script: String) async throws(SourceProblems) -> SourceResult
}

extension DataSourceRunning {
  /// A fetch that reads nothing but plain GETs.
  public func fetch(_ source: DataSource, state: JSONValue?, now: Timestamp) async throws(SourceFailure)
    -> SourceResult
  {
    try await fetch(source, state: state, now: now, elsewhere: NoSourceReading())
  }
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

  public func fetch(_ source: DataSource, state: JSONValue?, now: Timestamp, elsewhere: any SourceReading)
    async throws(SourceFailure) -> SourceResult
  {
    let requests: [SourceRequest]
    do throws(SourceProblems) {
      let asked = try await ParseSandbox.run(source.script, .requests(state: state), now: now, timeout: timeout)
      requests = try DataSourceCheck.requests(from: asked)
    } catch {
      throw .script(error, sample: nil)
    }
    let responses: [SourceResponse]
    do throws(SourceProblems) {
      responses = try await fetcher.fetch(requests, elsewhere: elsewhere)
    } catch {
      throw .unreachable(error)
    }
    let sample = SourceSample(at: now, state: state, requests: requests, responses: responses)
    do throws(SourceProblems) {
      return try await replay(sample, script: source.script)
    } catch {
      throw .script(error, sample: sample)
    }
  }

  public func replay(_ sample: SourceSample, script: String) async throws(SourceProblems) -> SourceResult {
    let parsed = try await ParseSandbox.run(
      script, .parse(responses: sample.responses), now: sample.at, timeout: timeout)
    return SourceResult(try DataSourceCheck.output(from: parsed), sample: sample)
  }
}
