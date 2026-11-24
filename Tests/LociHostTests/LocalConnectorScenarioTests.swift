import Foundation
import LociConnect
import LociModel
import LociStore
import Testing

@testable import LociHost

/// CN-S13, CN-S15: this Mac's calendars and reminders after macOS asks, and the `gh` that reads beside
/// GitHub's MCP tools.
@Suite(.timeLimit(.minutes(1)))
struct LocalConnectorScenarioTests {
  static let calendar = ConnectorID("calendar")

  private func text(_ reply: LocalReply?) throws -> String {
    guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
    return try JSONDecoder().decode(String.self, from: data)
  }

  private func refusal(_ reply: LocalReply?) -> String? {
    if case .failed(.invalidRequest(let why))? = reply { why } else { nil }
  }

  @Test func theCalendarConnectsWhenThePersonAllowsItAndReadsOnly() async throws {
    let world = ConnectWorld()
    world.personal.allow(.events, true)
    try await withHost(connect: world.environment) { host, _, _ in
      #expect(try await host.run(Connect(Self.calendar)) == .connected)
      let calendar = try #require(try await host.connectors().connected.first)
      #expect(calendar.source == .local && calendar.server.absoluteString == "x-apple-calendar://")
      #expect(calendar.tools.map(\.name) == ["calendars", "events"])

      let read = try text(
        await Background.call(CallConnector(Self.calendar, tool: "events"), from: .conversation(.main), on: host))
      #expect(read.contains("<external-content connector=\"calendar\" tool=\"events\">") && read.contains("组会"))
      let write = refusal(
        await Background.call(CallConnector(Self.calendar, tool: "add_event"), from: .conversation(.main), on: host))
      #expect(write?.contains("there is no tool add_event") == true)
      let calls = try await host.connectorCalls(limit: 10)
      #expect(
        calls.map(\.outcome).contains(.read) && calls.contains { if case .refused = $0.outcome { true } else { false } }
      )
    }
  }

  @Test func refusingInMacOSLeavesItUnconnectedAndSaysWhereToAllowIt() async throws {
    let world = ConnectWorld()
    world.personal.allow(.reminders, false)
    try await withHost(connect: world.environment) { host, _, _ in
      await #expect(throws: HostError.self) { try await host.run(Connect(ConnectorID("reminders"))) }
      let page = try await host.connectors()
      #expect(page.connected.isEmpty)
      guard case .failed(let why)? = page.attempts[ConnectorID("reminders")] else {
        throw HostError.notFound("attempt")
      }
      #expect(why.contains("System Settings"))
    }
  }

  @Test func takingAccessAwayInMacOSAsksForReconnecting() async throws {
    let world = ConnectWorld()
    world.personal.allow(.reminders, true)
    try await withHost(connect: world.environment) { host, _, _ in
      _ = try await host.run(Connect(ConnectorID("reminders")))
      world.personal.allow(.reminders, false)

      let why = refusal(
        await Background.call(
          CallConnector(ConnectorID("reminders"), tool: "reminders"), from: .conversation(.main), on: host))

      #expect(why?.contains("needs reconnecting") == true)
      #expect(try await host.connectors().connected.first.map { $0.status != .ready } == true)
    }
  }

  @Test func githubOffersGhBesideItsMCPToolsAndGhOnlyReads() async throws {
    let world = ConnectWorld()
    try await withHost(connect: world.environment) { host, _, _ in
      _ = try await host.run(Connect(ConnectorID("github")))
      let github = try #require(try await host.connectors().connected.first)
      #expect(github.tools.last?.name == "gh" && github.tools.count > 1)

      let log = try text(
        await Background.call(
          CallConnector(ConnectorID("github"), tool: "gh", arguments: #"{"args": ["run", "view", "123", "--log"]}"#),
          from: .run(EntityID()), on: host))
      let merge = refusal(
        await Background.call(
          CallConnector(ConnectorID("github"), tool: "gh", arguments: #"{"args": ["pr", "merge", "12"]}"#),
          from: .conversation(.main), on: host))
      let post = refusal(
        await Background.call(
          CallConnector(
            ConnectorID("github"), tool: "gh", arguments: #"{"args": ["api", "-X", "POST", "repos/o/r/issues"]}"#),
          from: .conversation(.main), on: host))

      #expect(log.contains("TestSnapshotRestore") && log.contains("tool=\"gh run view\""))
      #expect(merge?.contains("pr merge") == true && post?.contains("not a GET") == true)
      #expect(world.gh.runs == [["run", "view", "123", "--log"]])
      let outcomes = try await host.connectorCalls(limit: 10).map(\.outcome)
      #expect(outcomes.filter { if case .refused = $0 { true } else { false } }.count == 2)
    }
  }
}
