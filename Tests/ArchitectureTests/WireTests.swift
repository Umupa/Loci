import Testing

/// Every command and subscription crosses to other Macs only through the registry, so none may be missing.
struct WireTests {
  @Test func everyCommandAndSubscriptionIsRegistered() throws {
    let model = try Repository.files(in: "Sources").filter { $0.module == "LociModel" }
    let registry = try #require(model.first { $0.path == Architecture.wireRegistry })
    report(Self.unregistered(in: model, registry: registry))
  }

  @Test func flagsATypeMissingFromTheRegistry() {
    let commands = SourceFile(
      path: "Sources/LociModel/Example.swift", module: "LociModel",
      text: """
        public struct Listed: Command {}
        public struct Forgotten: Command {}
        public struct Watched: Subscription {}
        """)
    let registry = SourceFile(
      path: Architecture.wireRegistry, module: "LociModel",
      text: "let commands = [.reads(Listed.self)]\nlet subscriptions = [Watched.self]")

    #expect(Self.unregistered(in: [commands, registry], registry: registry).map(\.found) == ["Forgotten"])
  }

  static func unregistered(in files: [SourceFile], registry: SourceFile) -> [Violation] {
    let listed = Set(
      registry.lines.flatMap { line in line.code.matches(of: /\b(\w+)\.self\b/).map { String($0.1) } })
    return files.flatMap { file in
      file.lines.compactMap { line -> Violation? in
        guard let match = line.code.firstMatch(of: /\bstruct\s+(\w+)\s*:\s*(?:Command|Subscription)\b/),
          !listed.contains(String(match.1))
        else { return nil }
        return Violation(
          file: file.path, line: line.number, found: String(match.1),
          fix: "Add `\(match.1).self` to \(Architecture.wireRegistry): commands as `.reads` or `.writes`, "
            + "on the `.data` lane when the reply is bytes such as a PDF or a picture.")
      }
    }
  }
}
