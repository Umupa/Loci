import Foundation

/// A quantity the subject turns on: a title, the figure, and a line on what it means.
public struct AtlasFigure: Hashable, Codable, Sendable {
  public let title: AtlasText
  public let value: AtlasText
  @Omittable public var note: AtlasText?
}

/// One box of a flow or a dive.
public struct AtlasStep: Hashable, Codable, Sendable {
  @Omittable public var label: AtlasText?
  public let title: AtlasText
  @Omittable public var points: [AtlasText]
  /// The step the rest turns on, drawn in amber.
  @Omittable public var key: Bool
  @Omittable public var lessons: [Lesson.ID]
}

public struct AtlasFlow: Hashable, Codable, Sendable {
  public let title: AtlasText
  @Omittable public var lede: AtlasText?
  @Omittable public var lessons: [Lesson.ID]
  public let steps: [AtlasStep]
  /// A line under the flow for the path that goes around it.
  @Omittable public var aside: AtlasText?
}

public struct AtlasLayer: Hashable, Codable, Sendable {
  public let text: AtlasText
  /// The layer this column is about, drawn in amber.
  @Omittable public var marked: Bool
}

public struct AtlasColumn: Hashable, Codable, Sendable {
  public let title: AtlasText
  @Omittable public var note: AtlasText?
  /// From the top of the stack down.
  public let layers: [AtlasLayer]
  @Omittable public var verdict: AtlasText?
}

public struct AtlasLayers: Hashable, Codable, Sendable {
  public let title: AtlasText
  @Omittable public var lede: AtlasText?
  @Omittable public var lessons: [Lesson.ID]
  public let columns: [AtlasColumn]
}

public struct AtlasCard: Hashable, Codable, Sendable {
  @Omittable public var label: AtlasText?
  public let title: AtlasText
  public let points: [AtlasText]
  /// How it fails: what breaks it and what that looks like.
  @Omittable public var breaks: AtlasText?
  @Omittable public var lessons: [Lesson.ID]
}

public struct AtlasCards: Hashable, Codable, Sendable {
  public let title: AtlasText
  @Omittable public var lede: AtlasText?
  @Omittable public var lessons: [Lesson.ID]
  public let cards: [AtlasCard]
}

public struct AtlasDive: Hashable, Codable, Sendable {
  public let lesson: Lesson.ID
  public let title: AtlasText
  @Omittable public var lede: AtlasText?
  public let steps: [AtlasStep]
  @Omittable public var keep: [AtlasText]
}

public struct AtlasRow: Hashable, Codable, Sendable {
  public let label: AtlasText
  /// One per column; nil for a cell the person has not read about yet.
  public let cells: [AtlasText?]
  /// A row where the systems differ most, drawn in amber.
  @Omittable public var key: Bool
  @Omittable public var lessons: [Lesson.ID]
}

public struct AtlasTable: Hashable, Codable, Sendable {
  public let title: AtlasText
  @Omittable public var lede: AtlasText?
  @Omittable public var lessons: [Lesson.ID]
  public let columns: [AtlasText]
  public let rows: [AtlasRow]
}

/// A value the writer may leave out of the JSON: an empty list, false, or nothing.
@propertyWrapper
public struct Omittable<Value: Hashable & Codable & Sendable & OmittedValue>: Hashable, Codable, Sendable {
  public var wrappedValue: Value

  public init(wrappedValue: Value) {
    self.wrappedValue = wrappedValue
  }

  public init(from decoder: any Decoder) throws {
    wrappedValue = try Value(from: decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    try wrappedValue.encode(to: encoder)
  }
}

/// What an omitted value reads as.
public protocol OmittedValue {
  static var omitted: Self { get }
  var isOmitted: Bool { get }
}

extension Array: OmittedValue {
  public static var omitted: Self { [] }
  public var isOmitted: Bool { isEmpty }
}

extension Bool: OmittedValue {
  public static var omitted: Self { false }
  public var isOmitted: Bool { !self }
}

extension Optional: OmittedValue {
  public static var omitted: Self { nil }
  public var isOmitted: Bool { self == nil }
}

extension KeyedDecodingContainer {
  public func decode<Value>(_ type: Omittable<Value>.Type, forKey key: Key) throws -> Omittable<Value> {
    if !contains(key) { return Omittable(wrappedValue: .omitted) }
    if try decodeNil(forKey: key) { return Omittable(wrappedValue: .omitted) }
    return Omittable(wrappedValue: try decode(Value.self, forKey: key))
  }
}

extension KeyedEncodingContainer {
  public mutating func encode<Value>(_ value: Omittable<Value>, forKey key: Key) throws {
    guard !value.wrappedValue.isOmitted else { return }
    try encode(value.wrappedValue, forKey: key)
  }
}
