import Foundation

/// One thing a source reads, as `requests(state)` asks for it: a GET, a page rendered with the built-in
/// browser's sign-in, or a connector's read-only tool. There is nothing to choose that writes.
public enum SourceRequest: Hashable, Sendable {
  case get(SourceGet)
  /// A page as `loci read` reads it, signed in when its site is connected.
  case page(URL)
  case connector(SourceConnectorCall)

  /// The address a response to it is given under.
  public var address: URL {
    switch self {
    case .get(let get): get.url
    case .page(let url): url
    case .connector(let call): call.address
    }
  }
}

/// A GET over the network as no one.
public struct SourceGet: Hashable, Codable, Sendable {
  public let url: URL
  public let referer: String?
  public let userAgent: String?
  public let encoding: SourceEncoding?

  public init(url: URL, referer: String? = nil, userAgent: String? = nil, encoding: SourceEncoding? = nil) {
    self.url = url
    self.referer = referer
    self.userAgent = userAgent
    self.encoding = encoding
  }
}

/// A connector's read-only tool, called as `loci connector call` calls it.
public struct SourceConnectorCall: Hashable, Codable, Sendable {
  public let connector: ConnectorID
  public let tool: String
  /// One JSON object.
  public let arguments: JSONValue

  public init(connector: ConnectorID, tool: String, arguments: JSONValue) {
    self.connector = connector
    self.tool = tool
    self.arguments = arguments
  }

  /// `connector://<id>/<tool>`, the address its response is given under.
  public var address: URL {
    URL(string: "connector://\(connector.rawValue)")?.appending(path: tool) ?? URL(filePath: "/")
  }
}

extension SourceRequest: Codable {
  private enum CodingKeys: String, CodingKey {
    case page, connector
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let page = try container.decodeIfPresent(URL.self, forKey: .page) {
      self = .page(page)
    } else if container.contains(.connector) {
      self = .connector(try SourceConnectorCall(from: decoder))
    } else {
      self = .get(try SourceGet(from: decoder))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .get(let get): try get.encode(to: encoder)
    case .page(let url):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(url, forKey: .page)
    case .connector(let call): try call.encode(to: encoder)
    }
  }
}

/// Reads what a source asks for that is not a plain GET: pages and connectors, which the host holds the
/// sign-ins for. Gives the text as it came, not marked as content from outside, since `parse` is no model.
public protocol SourceReading: Sendable {
  func read(_ request: SourceRequest) async throws(SourceProblems) -> String
}

/// For where nothing but plain GETs is read.
public struct NoSourceReading: SourceReading {
  public init() {}

  public func read(_ request: SourceRequest) async throws(SourceProblems) -> String {
    throw SourceProblems("requests", "\(request.address.absoluteString) cannot be read here")
  }
}

/// Why a fetch got nothing: what it asked for could not be read, which may pass by itself, or its script
/// failed, which only a new script mends.
public enum SourceFailure: Error, Hashable, Sendable {
  case unreachable(SourceProblems)
  /// `requests` or `parse` threw, ran too long, or gave the wrong shape; `sample` is what `parse` was given,
  /// when it got that far.
  case script(SourceProblems, sample: SourceSample?)

  public var problems: SourceProblems {
    switch self {
    case .unreachable(let problems), .script(let problems, _): problems
    }
  }
}
