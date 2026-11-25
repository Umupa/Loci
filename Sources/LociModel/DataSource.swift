import Foundation

/// Something the app fetches by itself, with no model in the way: Loci's `requests(state)` says what to GET,
/// and its `parse(responses, now)` turns the answers into records that panel rows point at.
public struct DataSource: Hashable, Codable, Sendable {
  /// Short lowercase English, as a panel's: `etf-premium`.
  public let name: String
  public let title: String
  public let every: SourceEvery
  /// `nil` when it is fetched at any time of day.
  public let window: SourceWindow?
  /// JavaScript that declares `requests(state)` and `parse(responses, now)`.
  public let script: String

  public init(name: String, title: String, every: SourceEvery, window: SourceWindow? = nil, script: String) {
    self.name = name
    self.title = title
    self.every = every
    self.window = window
    self.script = script
  }

  /// The same source running another script, as `loci source test` tries one.
  public func running(_ script: String) -> DataSource {
    DataSource(name: name, title: title, every: every, window: window, script: script)
  }
}

/// How often a source is fetched while the window is in front, in whole minutes: written `1m`, `15m`, `1h`.
public struct SourceEvery: Hashable, Sendable, TextCodable {
  public let minutes: Int

  public init?(minutes: Int) {
    guard minutes >= 1 else { return nil }
    self.minutes = minutes
  }

  public init?(_ description: String) {
    guard let match = description.wholeMatch(of: /(\d{1,4})([mh])/), let count = Int(match.1) else { return nil }
    self.init(minutes: match.2 == "h" ? count * 60 : count)
  }

  public var description: String {
    minutes.isMultiple(of: 60) ? "\(minutes / 60)h" : "\(minutes)m"
  }
}

/// The part of the day a source is fetched in, in the person's time zone, such as a market's trading hours.
public struct SourceWindow: Hashable, Codable, Sendable, CustomStringConvertible {
  public let from: TimeOfDay
  public let to: TimeOfDay
  /// Only Monday to Friday.
  public let weekdays: Bool

  public init?(from: TimeOfDay, to: TimeOfDay, weekdays: Bool = false) {
    guard from < to else { return nil }
    self.from = from
    self.to = to
    self.weekdays = weekdays
  }

  /// Reads `09:30-15:00`.
  public init?(_ text: String, weekdays: Bool = false) {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2, let from = TimeOfDay(String(parts[0])), let to = TimeOfDay(String(parts[1])) else {
      return nil
    }
    self.init(from: from, to: to, weekdays: weekdays)
  }

  public var description: String { "\(from)-\(to)\(weekdays ? " on weekdays" : "")" }
}

/// A source, wherever it belongs: `home/etf-premium` for the chat's, `projects/<id>/etf-premium` for a
/// project's. What snapshots and readings are found by.
public struct SourceKey: Hashable, Sendable, TextCodable, CodingKeyRepresentable {
  public let home: Home
  public let name: String

  public init(_ home: Home, _ name: String) {
    self.home = home
    self.name = name
  }

  public init?(_ description: String) {
    let parts = description.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    switch parts.count {
    case 2 where parts[0] == Self.chat && !parts[1].isEmpty:
      self.init(.chat, parts[1])
    case 3 where parts[0] == "projects" && !parts[2].isEmpty:
      guard let project = EntityID(canonical: parts[1]) else { return nil }
      self.init(.project(project), parts[2])
    default:
      return nil
    }
  }

  private static let chat = "home"

  public var description: String {
    switch home {
    case .chat: "\(Self.chat)/\(name)"
    case .project: home.folder + name
    }
  }

  public var codingKey: any CodingKey { SourceCodingKey(stringValue: description) }

  public init?<T: CodingKey>(codingKey: T) {
    self.init(codingKey.stringValue)
  }
}

private struct SourceCodingKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }

  init(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue: Int) { nil }
}

/// A value of a record, as a panel row points at it: `<source>.<record>.<field>`, such as
/// `etf-premium.513870.premium`.
public struct SourceField: Hashable, Sendable, TextCodable {
  public let source: String
  public let record: String
  public let field: String

  public init?(source: String, record: String, field: String) {
    guard DataSourceCheck.problems(ofName: source).isEmpty, DataSourceCheck.isKey(record),
      DataSourceCheck.isKey(field)
    else { return nil }
    self.source = source
    self.record = record
    self.field = field
  }

  public init?(_ description: String) {
    let parts = description.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 3 else { return nil }
    self.init(source: parts[0], record: parts[1], field: parts[2])
  }

  public var description: String { "\(source).\(record).\(field)" }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let field = SourceField(text) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "\"\(text)\" is not written <source>.<record>.<field>")
    }
    self = field
  }
}
