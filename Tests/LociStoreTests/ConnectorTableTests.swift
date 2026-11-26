import Foundation
import LociModel
import Testing

@testable import LociStore

/// CN-S2, CN-S5: what the app keeps about connectors, and the record of every call.
struct ConnectorTableTests {
  static let notion = ConnectorRecord(
    id: ConnectorID("notion"), name: "Notion", kind: .mcp(URL(string: "https://mcp.notion.com/mcp")!),
    server: URL(string: "https://mcp.notion.com/mcp")!, account: nil, status: .ready, connectedAt: Fixture.instant,
    tools: [.init(name: "search", description: "Search", inputSchema: "{}", readOnly: true)], signedIn: true)

  static func call(_ seed: UInt64, minutes: Int64, _ caller: ConnectorCall.Caller, _ outcome: ConnectorCall.Outcome)
    -> ConnectorCall
  {
    ConnectorCall(
      id: Fixture.id(seed),
      at: Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + minutes * 60_000),
      caller: caller, connector: ConnectorID("notion"), tool: "search", outcome: outcome)
  }

  @Test func aConnectorIsKeptAsItWasLastSaved() throws {
    let database = try StoreDatabase.inMemory()
    try database.saveConnector(Self.notion)

    try database.saveConnector(Self.notion.with(status: .needsReconnecting("the sign-in ran out")))

    #expect(try database.connectorRecords() == [Self.notion.with(status: .needsReconnecting("the sign-in ran out"))])
  }

  @Test func disconnectingRemovesTheConnectorButKeepsItsCalls() throws {
    let database = try StoreDatabase.inMemory()
    try database.saveConnector(Self.notion)
    try database.logConnectorCall(Self.call(10, minutes: 0, .conversation(.main), .read))

    try database.removeConnector(ConnectorID("notion"))

    #expect(try database.connectorRecord(ConnectorID("notion")) == nil)
    #expect(try database.connectorCalls(limit: 10).count == 1)
  }

  @Test func callsComeNewestFirstAndCanBeFoundByTimeOrByWhoMadeThem() throws {
    let database = try StoreDatabase.inMemory()
    let run = Fixture.id(30)
    let calls = [
      Self.call(10, minutes: 0, .conversation(.main), .read),
      Self.call(11, minutes: 5, .run(run), .refused("create_page is not read-only")),
      Self.call(12, minutes: 9, .run(run), .failed("offline")),
    ]
    for call in calls { try database.logConnectorCall(call) }

    #expect(try database.connectorCalls(limit: 2) == [calls[2], calls[1]])
    #expect(try database.connectorCalls(since: calls[1].at) == [calls[1], calls[2]])
    #expect(try database.connectorCalls(by: .run(run)) == [calls[1], calls[2]])
  }

  @Test func aProjectDeletedForGoodTakesItsSourcesCallsButNotTheChatsOrAnotherProjects() throws {
    let database = try StoreDatabase.inMemory()
    let project = Fixture.id(40)
    let other = Fixture.id(41)
    try database.logConnectorCall(Self.call(10, minutes: 0, .source(SourceKey(.project(project), "prem")), .read))
    try database.logConnectorCall(Self.call(11, minutes: 1, .source(SourceKey(.project(other), "prem")), .read))
    try database.logConnectorCall(Self.call(12, minutes: 2, .source(SourceKey(.chat, "prem")), .read))

    try database.forgetProject(project)

    #expect(try database.connectorCalls(limit: 10).map(\.id).sorted() == [Fixture.id(11), Fixture.id(12)])
  }
}
