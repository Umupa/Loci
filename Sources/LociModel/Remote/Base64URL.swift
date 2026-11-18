import Foundation

/// Base64 with the URL-safe alphabet and no padding, as relay tokens and invite links use it.
public enum Base64URL {
  public static func encode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  /// `nil` for characters outside the alphabet, padding, or a length no encoding produces.
  public static func decode(_ text: String) -> Data? {
    guard text.wholeMatch(of: /[A-Za-z0-9_-]*/) != nil, text.count % 4 != 1 else { return nil }
    let standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let padded = standard + String(repeating: "=", count: (4 - standard.count % 4) % 4)
    guard let data = Data(base64Encoded: padded), encode(data) == text else { return nil }
    return data
  }
}
