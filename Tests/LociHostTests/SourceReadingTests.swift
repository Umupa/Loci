import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// DS-S5: a source may read a page of a site signed into in the built-in browser, and a connector's read-only
/// tools, as the companion reads them: GET only, each call recorded as the source's, and what came handed to
/// `parse` as it came.
@Suite(.timeLimit(.minutes(1)))
struct SourceReadingTests {
  static let github = ConnectorID("github")

  @Test func aSourceReadsASignedInPageAndAConnectorAndTheCallsAreRecorded() async throws {
    let world = ConnectWorld()
    world.sites.signIn("x.com", cookie: "auth_token")
    let runner = FakeSources(records: ["a": ["v": .number(1)]])
    runner.ask([
      .page(URL(string: "https://x.com/umupa")!),
      .connector(
        SourceConnectorCall(
          connector: Self.github, tool: "gh", arguments: .object(["args": .array([.string("api"), .string("x")])]))),
    ])
    try await withHost(connect: world.environment, sources: runner) { host, _, _ in
      _ = try await host.run(Connect(Self.github))
      _ = await value(host.subscribe(WatchConnectors())) { $0.connected.contains { $0.id == ConnectorID("x") } }

      let outcome = try await host.run(SaveDataSource(SourceLineTests.source()))

      #expect(outcome == .records(["a": ["v": .number(1)]]))
      #expect(runner.read == [FakeSites.page, "build failed: TestSnapshotRestore\n"])
      #expect(world.sites.read == [URL(string: "https://x.com/umupa")!])
      #expect(world.gh.runs == [["api", "x"]])
      let calls = try await host.connectorCalls(limit: 10)
      #expect(calls.map(\.caller) == [.source(SourceKey(.chat, "prem")), .source(SourceKey(.chat, "prem"))])
      #expect(calls.map(\.outcome) == [.read, .read])
    }
  }

  @Test func aConnectorCallThatWritesIsRefusedAndTheSourceIsNotSaved() async throws {
    let world = ConnectWorld()
    let runner = FakeSources()
    runner.ask([
      .connector(
        SourceConnectorCall(
          connector: Self.github, tool: "gh",
          arguments: .object(["args": .array(["api", "-X", "POST", "repos/o/r/issues"].map(JSONValue.string))])))
    ])
    try await withHost(connect: world.environment, sources: runner) { host, _, _ in
      _ = try await host.run(Connect(Self.github))

      let outcome = try await host.run(SaveDataSource(SourceLineTests.source()))

      guard case .failed(let problems) = outcome else {
        Issue.record("saved: \(outcome)")
        return
      }
      #expect(problems.all.first?.description.contains("not a GET") == true)
      #expect(world.gh.runs.isEmpty)
      #expect(try await host.run(ListDataSources()).isEmpty)
    }
  }
}
