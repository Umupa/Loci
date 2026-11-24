import Foundation
import Testing

/// Commands declare which registry may carry them. Subscriptions are always remote.
struct WireTests {
  @Test func everyCommandAndSubscriptionIsRegistered() throws {
    let model = try Repository.files(in: "Sources").filter { $0.module == "LociModel" }
    let registry = try #require(model.first { $0.path == Architecture.wireRegistry })
    report(Self.unregistered(in: model, registry: registry))
  }

  @Test func flagsATypeMissingFromTheRegistry() {
    let declarations = """
      public struct Listed: RemoteCommand {}
      public struct Forgotten: RemoteCommand {}
      public struct Watched: Subscription {}
      """
    let registry = "let commands = [.reads(Listed.self)]\nlet subscriptions = [Watched.self]"
    #expect(Self.problems(declarations, registry).map(\.found) == ["Forgotten"])
  }

  @Test func aRemoteCommandRegisteredOnlyForTheLocalToolIsRejected() {
    let declarations = "public struct OpenLesson: RemoteCommand {}"
    let registry = "let toolCommands = [OpenLesson.self]\nlet commands = []\nlet subscriptions = []"
    #expect(Self.problems(declarations, registry).map(\.found) == ["OpenLesson"])
  }

  @Test func aHostOnlyCommandMustBeRegisteredAsOne() {
    let declarations = """
      public struct Connect: HostOnlyCommand {}
      public struct Cancel: HostOnlyCommand {}
      """
    let registry = """
      let commands = [.writes(Cancel.self)]
      let hostOnlyCommands = [Connect.self]
      let subscriptions = []
      """
    #expect(Self.problems(declarations, registry).map(\.found) == ["Cancel"])
  }

  @Test func duplicateAndCrossRegisteredCommandsAreRejected() {
    let declarations = """
      public struct OpenLesson: RemoteCommand {}
      public struct ReadSource: LocalToolCommand {}
      """
    let registry = """
      let commands = [.writes(OpenLesson.self), .reads(ReadSource.self)]
      let toolCommands = [ReadSource.self]
      let subscriptions = [OpenLesson.self]
      """
    #expect(Self.problems(declarations, registry).map(\.found) == ["OpenLesson", "ReadSource"])
    #expect(
      Self.problems(
        "public struct ReadSource: LocalToolCommand {}", "let toolCommands = [ReadSource.self, ReadSource.self]"
      ).map(\.found) == ["ReadSource"])
  }

  @Test func registrationDoesNotReplaceAnExplicitCommandScope() {
    let declarations = """
      public final class OpenLesson:
        Command, Sendable {}
      """
    #expect(Self.problems(declarations, "let commands = [.writes(OpenLesson.self)]").map(\.found) == ["OpenLesson"])
  }

  private static func problems(_ declarations: String, _ registry: String) -> [Violation] {
    let model = SourceFile(path: "Sources/LociModel/Example.swift", module: "LociModel", text: declarations)
    let wire = SourceFile(path: Architecture.wireRegistry, module: "LociModel", text: registry)
    return unregistered(in: [model], registry: wire)
  }

  static func unregistered(in files: [SourceFile], registry: SourceFile) -> [Violation] {
    let wire = registry.lines.map(\.code).joined(separator: "\n")
    var registrations: [String: [String]] = [:]
    for table in wire.matches(
      of: /\blet\s+(commands|toolCommands|hostOnlyCommands|subscriptions)\b[^=\n]*=\s*\[([^\]]*)\]/)
    {
      for registered in table.2.matches(of: /\b(\w+)\.self\b/) {
        registrations[String(registered.1), default: []].append(String(table.1))
      }
    }
    return files.flatMap { file in
      let code = file.lines.map(\.code).joined(separator: "\n")
      let declarations = code.matches(
        of: /\bpublic\s+(?:final\s+)?(?:struct|enum|class)\s+(\w+)\s*:\s*([^{}]+)\{/
      )
      return declarations.compactMap { declaration -> Violation? in
        let line = code[..<declaration.range.lowerBound].reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
        let conformances = declaration.2.split(separator: ",").map {
          $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let name = String(declaration.1)
        let allowed = [
          "RemoteCommand": "commands", "LocalToolCommand": "toolCommands", "HostOnlyCommand": "hostOnlyCommands",
          "Subscription": "subscriptions",
        ]
        let tables = conformances.compactMap { allowed[$0] }
        if tables.isEmpty {
          guard conformances.contains("Command") else { return nil }
          return Violation(
            file: file.path, line: line, found: name,
            fix: "Declare `\(name)` as `RemoteCommand`, `LocalToolCommand` or `HostOnlyCommand`.")
        }
        guard tables.count != 1 || registrations[name] != tables else { return nil }
        return Violation(
          file: file.path, line: line, found: name,
          fix:
            "Register `\(name).self` exactly once in the corresponding `Wire` table: \(tables.joined(separator: ", "))."
        )
      }
    }
  }
}
