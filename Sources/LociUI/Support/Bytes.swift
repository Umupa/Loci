import Foundation

/// Sizes as the Finder says them: `198 MB`, `1.4 GB`.
enum Bytes {
  static func text(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file))
  }
}
