import Foundation

/// The gate a source and what its script gives pass through, naming every problem where it is.
public enum DataSourceCheck {
  /// At most this many requests in one fetch.
  public static let mostRequests = 20

  /// Everything wrong with a source before it is run; empty when it can be tried.
  public static func problems(in source: DataSource) -> [SourceProblem] {
    var found = problems(ofName: source.name)
    if source.title.isBlank { found.append(SourceProblem("title", "is empty")) }
    if source.script.isBlank {
      found.append(SourceProblem("script", "is empty; declare requests(state) and parse(responses, now)"))
    }
    return found
  }

  /// A short name in lowercase English, as a panel's: `etf-premium`.
  public static func problems(ofName name: String) -> [SourceProblem] {
    guard name.wholeMatch(of: /[a-z][a-z0-9]*(-[a-z0-9]+)*/) != nil, name.count <= PanelCheck.longestName else {
      return [
        SourceProblem(
          "name",
          "\"\(name)\" is not a short lowercase English name, such as etf-premium (at most \(PanelCheck.longestName))")
      ]
    }
    return []
  }

  /// A record or field name a panel row can point at: letters, digits, `_` and `-`.
  public static func isKey(_ key: String) -> Bool {
    key.wholeMatch(of: /[A-Za-z0-9_-]+/) != nil
  }

  /// The requests `requests(state)` gave: an array of links, of `{ url, referer, userAgent, encoding }`, of
  /// `{ page }`, or of `{ connector, tool, arguments }`.
  public static func requests(from json: JSONValue) throws(SourceProblems) -> [SourceRequest] {
    guard let items = json.array else {
      throw SourceProblems("requests", "did not return an array of requests")
    }
    guard !items.isEmpty else { throw SourceProblems("requests", "returned no requests") }
    guard items.count <= mostRequests else {
      throw SourceProblems("requests", "returned \(items.count); at most \(mostRequests) in one fetch")
    }
    var found: [SourceProblem] = []
    var requests: [SourceRequest] = []
    for (index, item) in items.enumerated() {
      do throws(SourceProblems) {
        requests.append(try request(item, at: "requests[\(index)]"))
      } catch {
        found += error.all
      }
    }
    guard found.isEmpty else { throw SourceProblems(all: found) }
    return requests
  }

  private static func request(_ item: JSONValue, at path: String) throws(SourceProblems) -> SourceRequest {
    if let method = item["method"]?.string, method.uppercased() != "GET" {
      throw SourceProblems("\(path).method", "a source only sends GET")
    }
    if let connector = item["connector"] {
      guard let id = connector.string, !id.isEmpty, let tool = item["tool"]?.string, !tool.isEmpty else {
        throw SourceProblems(path, "a connector's request is { connector: \"github\", tool: \"gh\", arguments: {…} }")
      }
      let arguments = item["arguments"] ?? .object([:])
      guard case .object = arguments else { throw SourceProblems("\(path).arguments", "is not an object") }
      return .connector(SourceConnectorCall(connector: ConnectorID(rawValue: id), tool: tool, arguments: arguments))
    }
    if let page = item["page"] {
      return .page(try link(page.string ?? "", at: "\(path).page"))
    }
    guard let given = item.string ?? item["url"]?.string else {
      throw SourceProblems(path, "is not a link, or an object with \"url\", \"page\" or \"connector\"")
    }
    let url = try link(given, at: "\(path).url")
    var encoding: SourceEncoding?
    if let name = item["encoding"]?.string {
      encoding = SourceEncoding(rawValue: name.lowercased().replacing("utf8", with: "utf-8"))
      if encoding == nil { throw SourceProblems("\(path).encoding", "\"\(name)\" is not one of: utf-8, gbk") }
    }
    return .get(
      SourceGet(url: url, referer: item["referer"]?.string, userAgent: item["userAgent"]?.string, encoding: encoding))
  }

  private static func link(_ text: String, at path: String) throws(SourceProblems) -> URL {
    guard let url = URL(string: text), url.isWebLink else {
      throw SourceProblems(path, "\"\(text)\" is not an http(s) link")
    }
    return url
  }

  /// What `parse(responses, now)` gave: `{ records: { <record>: { <field>: value } }, entries: [...], state }`;
  /// a source that keeps only entries may leave out `records`.
  public static func output(from json: JSONValue) throws(SourceProblems) -> SourceOutput {
    guard case .object(let members) = json,
      case .object(let records)? = members["records"] ?? (members["entries"] == nil ? nil : .object([:]))
    else {
      throw SourceProblems("parse", "did not return { records: { <record>: { <field>: value } } }")
    }
    var found: [SourceProblem] = []
    var read: [String: SourceRecord] = [:]
    for (key, value) in records.sorted(by: { $0.key < $1.key }) {
      let path = "records[\"\(key)\"]"
      if !isKey(key) { found.append(SourceProblem(path, "use only letters, digits, _ and - in a record's name")) }
      guard case .object(let fields) = value else {
        found.append(SourceProblem(path, "is not an object of fields"))
        continue
      }
      var record: SourceRecord = [:]
      for (name, field) in fields.sorted(by: { $0.key < $1.key }) {
        if !isKey(name) {
          found.append(SourceProblem("\(path).\(name)", "use only letters, digits, _ and - in a field's name"))
        }
        if field == .null { continue }
        guard let value = SourceValue(json: field) else {
          found.append(SourceProblem("\(path).\(name)", "is not a number, text, points or candles"))
          continue
        }
        record[name] = value
      }
      read[key] = record
    }
    let entries = members["entries"].map { entries(from: $0, found: &found) } ?? []
    guard found.isEmpty else { throw SourceProblems(all: found) }
    let state = members["state"].flatMap { $0 == .null ? nil : $0 }
    return SourceOutput(records: read, entries: entries, state: state)
  }
}

extension String {
  fileprivate var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
