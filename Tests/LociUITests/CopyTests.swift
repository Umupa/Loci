import Foundation
import Testing

/// Every piece of interface text exists in English and Chinese, and none is written straight into a view.
struct CopyTests {
  static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

  /// The interface's source files. A value put into a key, as in `.loci("tools.ran \(count)")`, reads as
  /// `tools.ran %arg`, whether the catalog writes it `%lld` for a number or `%@` for text.
  static func sources() throws -> [(path: String, text: String)] {
    let folder = root.appending(path: "Sources/LociUI")
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }
    return try (files ?? []).filter { $0.pathExtension == "swift" }.map {
      ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8).replacing(/\\\([^)"]*\)/, with: "%arg"))
    }
  }

  static func catalog() throws -> [String: Set<String>] {
    let url = root.appending(path: "Sources/LociUI/Resources/Localizable.xcstrings")
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = json?["strings"] as? [String: [String: Any]] ?? [:]
    return Dictionary(
      strings.map { key, entry in
        (key.replacing(/%(lld|@)/, with: "%arg"), Set((entry["localizations"] as? [String: Any] ?? [:]).keys))
      }, uniquingKeysWith: { first, _ in first })
  }

  @Test func everyKeyUsedIsTranslatedIntoBothLanguages() throws {
    let catalog = try Self.catalog()
    for (path, text) in try Self.sources() {
      for match in text.matches(of: /(?:\.loci|String\(loci:)\(?\s*"([^"]+)"/) {
        let key = String(match.1)
        #expect(catalog[key] == ["en", "zh-Hans"], "\(path) uses \(key)")
        #expect(
          key.wholeMatch(of: /[a-z]+\.[A-Za-z]+(?: %(?:lld|@|arg))*/) != nil,
          "\(path) uses \(key): write keys as <lowercase area>.<camelCaseName>, two parts, so the unused-key check reads them"
        )
      }
    }
  }

  @Test func theCatalogHasNoUnusedKeys() throws {
    let used = Set(
      try Self.sources().flatMap { $0.text.matches(of: /"([a-z]+\.[A-Za-z]+(?: %arg)*)"/).map { String($0.1) } })

    let unused = Set(try Self.catalog().keys).subtracting(used).sorted()
    #expect(unused.isEmpty, "no source uses \(unused); delete them from Localizable.xcstrings")
  }

  @Test func viewsDoNotSpellOutText() throws {
    for (path, text) in try Self.sources() {
      for match in text.matches(of: /\b(Text|Button|Label|Toggle|Section|LabeledContent)\("/) {
        Issue.record("\(path): \(match.0) takes interface text; use .loci(\"key\") or Text(verbatim:) for data")
      }
    }
  }
}
