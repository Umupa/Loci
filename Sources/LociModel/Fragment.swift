/// The `key=value&…` part of a locator after `#`.
///
/// Values are percent-encoded only where needed: ASCII outside a small safe set is escaped, other
/// characters stay as written so a locator written in Markdown stays readable.
struct Fragment {
  private var values: [String: String] = [:]

  init?(_ text: Substring) {
    for pair in text.split(separator: "&", omittingEmptySubsequences: false) {
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2, !parts[0].isEmpty, values[String(parts[0])] == nil,
        let value = Self.decode(parts[1])
      else { return nil }
      values[String(parts[0])] = value
    }
  }

  var isEmpty: Bool { values.isEmpty }

  mutating func take(_ key: String) -> String? {
    values.removeValue(forKey: key)
  }

  static func join(_ pairs: [(String, String?)]) -> String {
    pairs.compactMap { key, value in value.map { "\(key)=\(encode($0))" } }.joined(separator: "&")
  }

  static func encode(_ text: String) -> String {
    var encoded = ""
    for scalar in text.unicodeScalars {
      if staysAsWritten(scalar) {
        encoded.unicodeScalars.append(scalar)
      } else {
        for byte in String(scalar).utf8 {
          encoded += "%" + String(byte, radix: 16, uppercase: true).leftPadded(to: 2)
        }
      }
    }
    return encoded
  }

  static func decode(_ text: Substring) -> String? {
    var bytes: [UInt8] = []
    var iterator = text.utf8.makeIterator()
    while let byte = iterator.next() {
      switch byte {
      case UInt8(ascii: "%"):
        guard let high = iterator.next().flatMap(hexValue), let low = iterator.next().flatMap(hexValue) else {
          return nil
        }
        bytes.append(high << 4 | low)
      case 0...0x20, 0x7F, UInt8(ascii: "="), UInt8(ascii: "#"):
        return nil
      default:
        bytes.append(byte)
      }
    }
    return String(validating: bytes, as: UTF8.self)
  }

  private static func staysAsWritten(_ scalar: Unicode.Scalar) -> Bool {
    if scalar.isASCII {
      return scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || "-._~/,".unicodeScalars.contains(scalar)
    }
    let hidden: Set<Unicode.GeneralCategory> = [
      .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator, .spaceSeparator,
    ]
    return !scalar.properties.isWhitespace && !hidden.contains(scalar.properties.generalCategory)
  }

  private static func hexValue(_ byte: UInt8) -> UInt8? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
    default: nil
    }
  }
}
