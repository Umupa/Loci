import Foundation

/// A reminder condition: a number of one of the home's sources compared with a threshold. Each refresh of the
/// source is checked by the app, with no model in the way; a card comes up only when the condition turns from
/// false to true, and not again within `cooldown` of the last one.
public struct NextUpCondition: Hashable, Codable, Sendable, Identifiable {
  public let id: EntityID
  public let home: Home
  public let field: SourceField
  public let comparison: Comparison
  public let threshold: Double
  /// The card's line; `{value}` is the number that made it true.
  public let say: String
  /// What starting the card says, as the person.
  public let ask: String
  /// Whether it held at the last refresh; `nil` before the first.
  public let holds: Bool?
  /// When it last brought a card up.
  public let firedAt: Timestamp?
  public let createdAt: Timestamp

  public static let cooldown: Int64 = 4 * 3_600_000

  public init(
    id: EntityID, home: Home, field: SourceField, comparison: Comparison, threshold: Double, say: String,
    ask: String, holds: Bool? = nil, firedAt: Timestamp? = nil, createdAt: Timestamp
  ) {
    self.id = id
    self.home = home
    self.field = field
    self.comparison = comparison
    self.threshold = threshold
    self.say = say
    self.ask = ask
    self.holds = holds
    self.firedAt = firedAt
    self.createdAt = createdAt
  }

  /// The source it watches.
  public var source: SourceKey { SourceKey(home, field.source) }

  /// The key of the cards it brings up: declining one stops it.
  public var key: String { "condition/\(id)" }

  /// Whether it holds for the snapshot; `nil` when the field is missing or not a number.
  public func holds(in snapshot: SourceSnapshot) -> Bool? {
    value(in: snapshot).map { comparison.holds($0, threshold) }
  }

  public func value(in snapshot: SourceSnapshot) -> Double? {
    snapshot.value(field)?.number
  }

  /// The condition after a refresh, and the card's line when it should bring one up. The first refresh only
  /// notes whether it holds; a missing value leaves it as it was.
  public func step(_ snapshot: SourceSnapshot, at now: Timestamp) -> (NextUpCondition, fired: String?) {
    guard let value = value(in: snapshot) else { return (self, nil) }
    let holdsNow = comparison.holds(value, threshold)
    let rested = firedAt.map { $0.millisecondsSince1970 + Self.cooldown <= now.millisecondsSince1970 } ?? true
    guard holds == false, holdsNow, rested else { return (with(holds: holdsNow, firedAt: firedAt), nil) }
    return (with(holds: true, firedAt: now), words(for: value))
  }

  public func with(holds: Bool?, firedAt: Timestamp?) -> NextUpCondition {
    NextUpCondition(
      id: id, home: home, field: field, comparison: comparison, threshold: threshold, say: say, ask: ask,
      holds: holds, firedAt: firedAt, createdAt: createdAt)
  }

  /// `say` with the value in place of `{value}`.
  public func words(for value: Double) -> String {
    say.replacingOccurrences(of: "{value}", with: Self.number(value))
  }

  /// How the condition reads in `loci next conditions`.
  public var line: String { "\(id)  \(field) \(comparison.rawValue) \(Self.number(threshold))  \(say)" }

  private static func number(_ value: Double) -> String {
    value.formatted(
      .number.grouping(.never).precision(.significantDigits(1...6)).locale(Locale(identifier: "en_US_POSIX")))
  }
}

public enum Comparison: String, Hashable, Codable, Sendable, CaseIterable {
  case below = "<"
  case atMost = "<="
  case above = ">"
  case atLeast = ">="

  public func holds(_ value: Double, _ threshold: Double) -> Bool {
    switch self {
    case .below: value < threshold
    case .atMost: value <= threshold
    case .above: value > threshold
    case .atLeast: value >= threshold
    }
  }
}
