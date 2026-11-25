import Foundation

/// A connector's id: the catalog's (`notion`, `linear`, `github`, …), or `mcp-<host>` for an address the
/// person added.
public struct ConnectorID: Hashable, Codable, Sendable, RawRepresentable, CodingKeyRepresentable,
  CustomStringConvertible
{
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

/// A connector that can be connected, as the catalog lists it.
public struct ConnectorOffer: Hashable, Codable, Sendable, Identifiable {
  public let id: ConnectorID
  public let name: String
  public let kind: Kind

  public enum Kind: Hashable, Codable, Sendable {
    /// Signs in in the browser with OAuth, at this MCP address.
    case mcp(URL)
    /// GitHub's read-only MCP address and the `gh` command, both with the `gh` signed in on this Mac.
    case github
    /// A website read with the sign-in of the built-in browser; connecting opens its sign-in page there.
    case site(signIn: URL)
    /// The calendars on this Mac, after macOS asks the person.
    case calendar
    /// The reminders on this Mac, after macOS asks the person.
    case reminders

    public var source: ConnectorSource {
      switch self {
      case .mcp, .github: .mcp
      case .site: .site
      case .calendar, .reminders: .local
      }
    }
  }

  public init(id: ConnectorID, name: String, kind: Kind) {
    self.id = id
    self.name = name
    self.kind = kind
  }

  public var source: ConnectorSource { kind.source }
}

/// Where a connector reads from, which the page marks it with: a service over MCP, a website signed into in
/// the built-in browser, or this Mac's own data.
public enum ConnectorSource: String, Hashable, Codable, Sendable {
  case mcp, site, local
}

/// A connected connector, as the Connectors page and `loci connector list` show it.
public struct Connector: Hashable, Codable, Sendable, Identifiable {
  public let id: ConnectorID
  public let name: String
  public let source: ConnectorSource
  /// The MCP address, the website, or the app on this Mac it reads.
  public let server: URL
  /// `nil` when the server does not say; the page shows the server's host then.
  public let account: String?
  public let status: Status
  /// Only the tools marked read-only: the rest are never offered to the companion.
  public let tools: [ConnectorTool]
  public let connectedAt: Timestamp
  public let readsToday: Int
  public let lastUsed: Timestamp?

  public enum Status: Hashable, Codable, Sendable {
    case ready
    /// Its sign-in ran out and could not be renewed, or `gh` is signed out; says why.
    case needsReconnecting(String)
  }

  public init(
    id: ConnectorID, name: String, source: ConnectorSource, server: URL, account: String?, status: Status,
    tools: [ConnectorTool], connectedAt: Timestamp, readsToday: Int, lastUsed: Timestamp?
  ) {
    self.id = id
    self.name = name
    self.source = source
    self.server = server
    self.account = account
    self.status = status
    self.tools = tools
    self.connectedAt = connectedAt
    self.readsToday = readsToday
    self.lastUsed = lastUsed
  }
}

/// A tool a connector offers that only reads.
public struct ConnectorTool: Hashable, Codable, Sendable {
  public let name: String
  public let description: String
  /// The tool's `inputSchema`, as JSON text.
  public let inputSchema: String

  public init(name: String, description: String, inputSchema: String) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
  }
}

/// A connection under way: waiting for the browser, or failed.
public enum ConnectAttempt: Hashable, Codable, Sendable {
  case waiting(until: Timestamp)
  case failed(String)
}

/// The Connectors page.
public struct Connectors: Hashable, Codable, Sendable {
  public let connected: [Connector]
  /// Not connected yet, in the catalog's order.
  public let available: [ConnectorOffer]
  /// The connection under way or failed, by connector, for one being connected or reconnected.
  public let attempts: [ConnectorID: ConnectAttempt]

  public init(connected: [Connector], available: [ConnectorOffer], attempts: [ConnectorID: ConnectAttempt]) {
    self.connected = connected
    self.available = available
    self.attempts = attempts
  }
}

/// What connecting gives the window: the page to open, in the default browser for an OAuth sign-in or in a
/// new tab of the built-in browser for a website, or nothing to open when the connector is ready already.
public enum Authorization: Hashable, Codable, Sendable {
  case open(URL)
  case openInBuiltInBrowser(URL)
  case connected
}

/// One call the companion made to a connector.
public struct ConnectorCall: Hashable, Codable, Sendable, Identifiable {
  public let id: EntityID
  public let at: Timestamp
  public let caller: Caller
  public let connector: ConnectorID
  public let tool: String
  public let outcome: Outcome

  public enum Caller: Hashable, Codable, Sendable {
    case conversation(ConversationRef)
    case run(Run.ID)
    /// A source the app fetches, which is given what it read as it came: its `parse` is no model.
    case source(SourceKey)

    /// As notes are tagged: `main`, `library/<id>`, `run/<id>`; a source's is `source/<key>`.
    public var tag: String {
      switch self {
      case .conversation(let conversation): conversation.tag
      case .run(let run): LocalSession.run(run).tag
      case .source(let source): "source/\(source)"
      }
    }
  }

  public enum Outcome: Hashable, Codable, Sendable {
    case read
    /// Not a read-only tool it has, or the connector needs reconnecting.
    case refused(String)
    case failed(String)
  }

  public init(
    id: EntityID, at: Timestamp, caller: Caller, connector: ConnectorID, tool: String, outcome: Outcome
  ) {
    self.id = id
    self.at = at
    self.caller = caller
    self.connector = connector
    self.tool = tool
    self.outcome = outcome
  }
}
