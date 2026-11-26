import Foundation

/// One item of a list a source reads, such as a news flash, a paper or an issue, known by its id. A panel
/// that follows the source's entries is offered the ones it has not seen.
public struct SourceEntry: Hashable, Codable, Sendable {
  public let id: String
  public let title: String
  public let url: URL?
  /// When it was published.
  public let at: Timestamp?
  /// A few words shown under the title, such as `+3.2%`.
  public let note: String?

  public init(id: String, title: String, url: URL? = nil, at: Timestamp? = nil, note: String? = nil) {
    self.id = id
    self.title = title
    self.url = url
    self.at = at
    self.note = note
  }
}

/// What one call of `parse` gave.
public struct SourceOutput: Hashable, Sendable {
  public let records: [String: SourceRecord]
  public let entries: [SourceEntry]
  /// What to keep for the next `requests`.
  public let state: JSONValue?

  public init(records: [String: SourceRecord], entries: [SourceEntry] = [], state: JSONValue? = nil) {
    self.records = records
    self.entries = entries
    self.state = state
  }
}

extension DataSourceCheck {
  /// At most this many entries in one fetch.
  public static let mostEntries = 200

  /// `entries: [{ id, title, url?, at?, note? }]`, `at` in milliseconds.
  static func entries(from json: JSONValue, found: inout [SourceProblem]) -> [SourceEntry] {
    guard let items = json.array else {
      found.append(SourceProblem("entries", "is not an array of { id, title, url, at, note }"))
      return []
    }
    guard items.count <= mostEntries else {
      found.append(SourceProblem("entries", "has \(items.count); at most \(mostEntries) in one fetch"))
      return []
    }
    var entries: [SourceEntry] = []
    var ids: Set<String> = []
    for (index, item) in items.enumerated() {
      let path = "entries[\(index)]"
      let id = item["id"]?.string ?? item["id"]?.int.map(String.init)
      guard let id, !id.isEmpty, let title = item["title"]?.string, !title.isEmpty else {
        found.append(SourceProblem(path, "needs an \"id\" and a \"title\""))
        continue
      }
      guard ids.insert(id).inserted else {
        found.append(SourceProblem("\(path).id", "\"\(id)\" is given twice"))
        continue
      }
      var url: URL?
      if let link = item["url"]?.string {
        url = URL(string: link).flatMap { $0.isWebLink ? $0 : nil }
        if url == nil { found.append(SourceProblem("\(path).url", "\"\(link)\" is not an http(s) link")) }
      }
      var at: Timestamp?
      if let given = item["at"], given != .null {
        at = given.number.flatMap(Timestamp.init(sourceMilliseconds:))
        if at == nil {
          let shown = given.number.map { "\($0) " } ?? ""
          found.append(SourceProblem("\(path).at", "\(shown)is not a time in milliseconds since 1970"))
        }
      }
      entries.append(SourceEntry(id: id, title: title, url: url, at: at, note: item["note"]?.string))
    }
    return entries
  }
}
