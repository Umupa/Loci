import Foundation
import Testing

/// Every piece of interface text exists in English and Chinese, and none is written straight into a view.
struct CopyTests {
  static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

  /// The interface's source files. A number put into a key, as in `.loci("tools.ran \(count)")`, reads as
  /// the catalog writes it: `tools.ran %lld`.
  static func sources() throws -> [(path: String, text: String)] {
    let folder = root.appending(path: "Sources/LociUI")
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }
    return try (files ?? []).filter { $0.pathExtension == "swift" }.map {
      ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8).replacing(/\\\([^)"]*\)/, with: "%lld"))
    }
  }

  static func catalog() throws -> [String: Set<String>] {
    let url = root.appending(path: "Sources/LociUI/Resources/Localizable.xcstrings")
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = json?["strings"] as? [String: [String: Any]] ?? [:]
    return strings.mapValues { entry in
      Set((entry["localizations"] as? [String: Any] ?? [:]).keys)
    }
  }

  @Test func everyKeyUsedIsTranslatedIntoBothLanguages() throws {
    let catalog = try Self.catalog()
    for (path, text) in try Self.sources() {
      for match in text.matches(of: /(?:\.loci|String\(loci:)\(?\s*"([^"]+)"/) {
        let key = String(match.1)
        #expect(catalog[key] == ["en", "zh-Hans"], "\(path) uses \(key)")
      }
    }
  }

  @Test func theCatalogHasNoUnusedKeys() throws {
    let used = Set(
      try Self.sources().flatMap { $0.text.matches(of: /"([a-z]+\.[A-Za-z]+(?: %lld)*)"/).map { String($0.1) } })

    #expect(Set(try Self.catalog().keys).subtracting(used).isEmpty)
  }

  @Test func viewsDoNotSpellOutText() throws {
    for (path, text) in try Self.sources() {
      for match in text.matches(of: /\b(Text|Button|Label|Toggle|Section|LabeledContent)\("/) {
        Issue.record("\(path): \(match.0) takes interface text; use .loci(\"key\") or Text(verbatim:) for data")
      }
    }
  }
}
