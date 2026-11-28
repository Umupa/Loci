import Foundation

/// The connectors: connected, to connect, and the connections under way.
public struct WatchConnectors: Subscription {
  public static let name = "connectors"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> Connectors {
    try await handler.connectors()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.connectors) || changes.contains(.everything)
  }
}

/// The companion's latest calls to connectors, newest first.
public struct WatchConnectorCalls: Subscription {
  public static let name = "connectors.calls"
  public let limit: Int

  public init(limit: Int = 100) {
    self.limit = limit
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> [ConnectorCall] {
    try await handler.connectorCalls(limit: limit)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.connectors) || changes.contains(.everything)
  }
}

/// Connects a connector from the catalog, or connects again one that needs it. Only on the Mac the
/// companion lives on: the browser comes back to that Mac.
public struct Connect: HostOnlyCommand {
  public static let name = "connectors.connect"
  public let connector: ConnectorID

  public init(_ connector: ConnectorID) {
    self.connector = connector
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Authorization {
    try await handler.connect(self)
  }
}

/// Connects an MCP server by its address, the same way as one from the catalog.
public struct AddMCPServer: HostOnlyCommand {
  public static let name = "connectors.addServer"
  public let address: URL

  public init(_ address: URL) {
    self.address = address
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Authorization {
    try await handler.addMCPServer(self)
  }
}

/// Stops waiting for the browser.
public struct CancelConnecting: HostOnlyCommand {
  public static let name = "connectors.cancel"
  public let connector: ConnectorID

  public init(_ connector: ConnectorID) {
    self.connector = connector
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.cancelConnecting(self)
  }
}

/// Deletes the connector's credentials; the companion no longer sees it. Its calls stay
/// in the record.
public struct Disconnect: RemoteCommand {
  public static let name = "connectors.disconnect"
  public let connector: ConnectorID

  public init(_ connector: ConnectorID) {
    self.connector = connector
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.disconnect(self)
  }
}

/// The connected connectors and the tools each can read with, for `loci connector list`.
public struct ListConnectors: LocalToolCommand {
  public static let name = "connectors.list"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> [Connector] {
    try await handler.connectors().connected
  }
}

/// Calls a read-only tool of a connector; the app adds the credentials. The reply is what the tool gave
/// back, marked as external content.
public struct CallConnector: LocalToolCommand {
  public static let name = "connectors.call"
  public let connector: ConnectorID
  public let tool: String
  /// A JSON object, as text.
  public let arguments: String

  public init(_ connector: ConnectorID, tool: String, arguments: String = "{}") {
    self.connector = connector
    self.tool = tool
    self.arguments = arguments
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> String {
    try await handler.callConnector(self, from: nil)
  }
}
