import LociModel

/// How one JSON value became another, small when little changed: a conversation that grew by a few words
/// sends those words, not the conversation.
public indirect enum JSONDelta: Hashable, Codable, Sendable {
  case replace(JSONValue)
  /// Changed and added members, and the names of removed ones.
  case object(changed: [String: JSONDelta], removed: [String])
  /// The first `kept` elements stay, with `changed` applied by index; `appended` follows them.
  case array(kept: Int, changed: [Int: JSONDelta], appended: [JSONValue])
  /// The string grew at its end.
  case appendText(String)

  /// `nil` when the values are equal.
  public static func from(_ old: JSONValue, to new: JSONValue) -> JSONDelta? {
    guard old != new else { return nil }
    switch (old, new) {
    case (.object(let before), .object(let after)):
      var changed: [String: JSONDelta] = [:]
      for (key, value) in after {
        if let previous = before[key] {
          if let delta = from(previous, to: value) { changed[key] = delta }
        } else {
          changed[key] = .replace(value)
        }
      }
      let removed = before.keys.filter { after[$0] == nil }.sorted()
      return .object(changed: changed, removed: removed)
    case (.array(let before), .array(let after)):
      let kept = min(before.count, after.count)
      var changed: [Int: JSONDelta] = [:]
      for index in 0..<kept {
        if let delta = from(before[index], to: after[index]) { changed[index] = delta }
      }
      return .array(kept: kept, changed: changed, appended: Array(after[kept...]))
    case (.string(let before), .string(let after)) where after.hasPrefix(before):
      return .appendText(String(after.dropFirst(before.count)))
    default:
      return .replace(new)
    }
  }

  /// The new value. A delta that does not fit the value it is applied to fails, which means the two sides
  /// disagree about the old value; the caller asks for the whole value again.
  public func apply(to old: JSONValue) throws(DeltaMismatch) -> JSONValue {
    switch (self, old) {
    case (.replace(let value), _):
      return value
    case (.object(let changed, let removed), .object(var members)):
      for key in removed { members[key] = nil }
      for (key, delta) in changed {
        members[key] = try delta.apply(to: members[key] ?? .null)
      }
      return .object(members)
    case (.array(let kept, let changed, let appended), .array(let elements)):
      guard kept <= elements.count else { throw DeltaMismatch() }
      var result = Array(elements.prefix(kept))
      for (index, delta) in changed {
        guard result.indices.contains(index) else { throw DeltaMismatch() }
        result[index] = try delta.apply(to: result[index])
      }
      return .array(result + appended)
    case (.appendText(let suffix), .string(let text)):
      return .string(text + suffix)
    default:
      throw DeltaMismatch()
    }
  }
}

public struct DeltaMismatch: Error, Hashable, Sendable {}
