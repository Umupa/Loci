import Foundation
import Testing

/// Module boundaries: who may import whom, and who owns each way out of the process.
struct BoundaryTests {
  @Test func everyModuleIsInTheMap() throws {
    let unknown = try Repository.directories(in: "Sources").filter { Architecture.modules[$0] == nil }

    report(
      unknown.map {
        Violation(
          file: "Sources/\($0)", line: 1, found: "module is not in the architecture map",
          fix: "Put the code in an existing module, or add a row to Tests/ArchitectureTests/Architecture.swift "
            + "and docs/architecture.md and explain the new module in the pull request.")
      })
  }

  @Test func modulesImportOnlyWhatTheMapAllows() throws {
    report(try Repository.files(in: "Sources").flatMap(Self.importViolations))
  }

  @Test func eachWayOutHasOneOwner() throws {
    report(
      try Repository.files(in: "Sources").flatMap { file in
        Self.violations(of: Architecture.restricted, in: file)
      })
  }

  static func importViolations(in file: SourceFile) -> [Violation] {
    guard let module = Architecture.modules[file.module] else { return [] }
    return file.imports.compactMap { line, name in
      if name.hasPrefix("Loci") {
        guard !module.uses.contains(name) else { return nil }
        return Violation(
          file: file.path, line: line, found: "\(file.module) imports \(name)",
          fix: "\(file.module) may use only \(module.uses.sorted()). Move the shared type down into LociModel, "
            + "or reach the behaviour through the Host protocol.")
      }
      guard !module.frameworks.contains(name) else { return nil }
      return Violation(
        file: file.path, line: line, found: "\(file.module) imports \(name)",
        fix: "\(file.module) may use only \(module.frameworks.sorted()). If \(name) truly belongs here, "
          + "add it to the map in the same pull request and say why.")
    }
  }

  static func violations(of restrictions: [Architecture.Restriction], in file: SourceFile) -> [Violation] {
    restrictions.flatMap { restriction -> [Violation] in
      guard !restriction.allowedIn.contains(file.module), let compiled = try? Regex(restriction.pattern) else {
        return []
      }
      let pattern = compiled.wordBoundaryKind(.simple)
      return file.lines.compactMap { line in
        guard let match = line.code.firstMatch(of: pattern) else { return nil }
        return Violation(
          file: file.path, line: line.number, found: String(line.code[match.range]), fix: restriction.fix)
      }
    }
  }
}
