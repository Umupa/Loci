import Foundation
import LociConnect
import LociModel
import LociStore

extension ConnectorKeeper {
  /// Calls a tool the connector marks read-only, with the credentials the app keeps, and records the call.
  /// The reply is marked as content from outside. Anything else is refused, and says why.
  func call(_ command: CallConnector, by caller: ConnectorCall.Caller) async throws(HostError) -> String {
    let id = command.connector
    func refuse(_ reason: String) async throws(HostError) -> Never {
      await log(command, caller, .refused(reason))
      throw .invalidRequest(reason)
    }
    guard var record = try attempt({ try database.connectorRecord(id) }) else {
      try await refuse("There is no connector \(id). Run `loci connector list` to see them.")
    }
    if case .needsReconnecting(let why) = record.status {
      try await refuse(Self.reconnect(record, why))
    }
    guard let arguments = JSONValue(parsing: command.arguments), case .object = arguments else {
      throw .invalidRequest("The arguments of a connector call are one JSON object, such as {\"query\": \"…\"}.")
    }
    if let answer = try await callOwn(command, arguments: arguments, record: record, by: caller) { return answer }
    if !record.tools.contains(where: { $0.name == command.tool }) {
      do throws(ConnectError) {
        record = try await refreshTools(of: record)
      } catch .needsReconnecting(let why) {
        try await refuse(Self.reconnect(record, why))
      } catch {
        await log(command, caller, .failed(error.reason))
        throw .invalidRequest("\(record.name) could not be read: \(error.reason)")
      }
    }
    guard record.tools.first(where: { $0.name == command.tool })?.readOnly == true else {
      try await refuse(
        "\(command.tool) is not one of \(record.name)'s read-only tools; connectors only read. "
          + "Run `loci connector list \(id)` to see what it can read.")
    }
    let server = record.server
    let result: CallResult
    do throws(ConnectError) {
      result = try await withToken(of: record) { token throws(ConnectError) in
        try await self.client(id, server).call(command.tool, arguments: arguments, token: token)
      }
    } catch .needsReconnecting(let why) {
      try await refuse(Self.reconnect(record, why))
    } catch {
      await log(command, caller, .failed(error.reason))
      throw .invalidRequest("\(record.name) could not be read: \(error.reason)")
    }
    await log(command, caller, .read)
    return Self.answer(
      caller,
      result.isError ? "The tool says it failed:\n" + result.text : result.text, from: id.rawValue, tool: command.tool)
  }

  /// Every connector's tools as the servers list them now; one that cannot be reached keeps what it had.
  func refreshAll() async {
    for record in (try? database.connectorRecords()) ?? [] where record.status == .ready && record.kind.source == .mcp {
      _ = try? await refreshTools(of: record)
    }
  }

  func refreshTools(of record: ConnectorRecord) async throws(ConnectError) -> ConnectorRecord {
    let tools = try await withToken(of: record) { token throws(ConnectError) in
      try await self.client(record.id, record.server).tools(token: token)
    }
    let refreshed = record.with(tools: Self.kept(tools, for: record.kind))
    if refreshed != record { try? database.saveConnector(refreshed) }
    return refreshed
  }

  /// Runs `body` with the token the connector signs in with now, renewing it first when it runs out, and
  /// once more when the server turns it away. A sign-in that cannot be renewed marks the connector for
  /// reconnecting.
  func withToken<Value: Sendable>(
    of record: ConnectorRecord, _ body: @Sendable (String?) async throws(ConnectError) -> Value
  ) async throws(ConnectError) -> Value {
    do throws(ConnectError) {
      switch record.kind {
      case .github:
        guard let login = await connect.githubLogin() else {
          throw .needsReconnecting("gh is not signed in on this Mac")
        }
        return try await body(login.token)
      case .site, .calendar, .reminders:
        throw .unsupported("\(record.name) is not an MCP server")
      case .mcp:
        guard record.signedIn else { return try await body(nil) }
        var credential = try credential(of: record)
        if credential.expires(by: environment.now()) { credential = try await renew(credential, of: record) }
        do throws(ConnectError) {
          return try await body(credential.accessToken)
        } catch .unauthorized {
          return try await body(try await renew(credential, of: record).accessToken)
        }
      }
    } catch .needsReconnecting(let why) {
      await mark(record, .needsReconnecting(why))
      throw .needsReconnecting(why)
    } catch .unauthorized {
      await mark(record, .needsReconnecting("the server no longer takes the sign-in"))
      throw .needsReconnecting("the server no longer takes the sign-in")
    }
  }

  private func renew(_ credential: MCPCredential, of record: ConnectorRecord) async throws(ConnectError)
    -> MCPCredential
  {
    let renewed = try await oauth.refresh(credential, now: environment.now())
    try keep(renewed, for: record.id)
    return renewed
  }

  private func credential(of record: ConnectorRecord) throws(ConnectError) -> MCPCredential {
    guard let data = try? connect.vault?.secret(for: record.id),
      let credential = try? JSONDecoder().decode(MCPCredential.self, from: data)
    else { throw .needsReconnecting("its sign-in is missing") }
    return credential
  }

  func mark(_ record: ConnectorRecord, _ status: Connector.Status) async {
    try? database.saveConnector(record.with(status: status))
    await follower.follow([.connectors])
  }

  func log(_ command: CallConnector, _ caller: ConnectorCall.Caller, _ outcome: ConnectorCall.Outcome) async {
    let call = ConnectorCall(
      id: environment.newID(), at: environment.now(), caller: caller, connector: command.connector, tool: command.tool,
      outcome: outcome)
    try? database.logConnectorCall(call)
    await follower.follow([.connectors])
  }

  /// What was read, marked as content from outside for a session; as it came for a source.
  static func answer(_ caller: ConnectorCall.Caller, _ text: String, from connector: String, tool: String) -> String {
    if case .source = caller { return text }
    return ExternalContent.wrap(text, from: connector, tool: tool)
  }

  static func reconnect(_ record: ConnectorRecord, _ why: String) -> String {
    "\(record.name) needs reconnecting (\(why)). Nothing was read. Tell the person they can reconnect it on the "
      + "Connectors page of your companion page."
  }
}
