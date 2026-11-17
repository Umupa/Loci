import Foundation
import Testing

/// Rules that hold in every source file.
struct CodeRuleTests {
  @Test func noForbiddenConstructs() throws {
    report(
      try Repository.files(in: "Sources").flatMap { file in
        BoundaryTests.violations(of: Architecture.forbidden, in: file)
      })
  }

  @Test func sourcesCarryNoComments() throws {
    report(try Repository.files(in: "Sources").flatMap(Self.commentViolations))
  }

  @Test func nothingIsLeftForLater() throws {
    let files = try Repository.files(in: "Sources") + Repository.files(in: "Tests")
    report(files.filter { !$0.path.hasSuffix("CodeRuleTests.swift") }.flatMap(Self.markerViolations))
  }

  @Test func sourceFilesStaySmall() throws {
    report(
      try Repository.files(in: "Sources").filter { $0.lines.count > Architecture.longestSourceFile }.map {
        Violation(
          file: $0.path, line: Architecture.longestSourceFile + 1,
          found: "\($0.lines.count) lines (limit \(Architecture.longestSourceFile))",
          fix: "The file does more than one thing. Split it by responsibility, one type or one concern per file.")
      })
  }

  @Test func everyLibraryModuleHasTests() throws {
    let tested = Set(try Repository.directories(in: "Tests"))
    let untested = try Repository.directories(in: "Sources").filter {
      Architecture.modules[$0]?.isExecutable == false && !tested.contains("\($0)Tests")
    }

    report(
      untested.map {
        Violation(
          file: "Sources/\($0)", line: 1, found: "no Tests/\($0)Tests",
          fix: "Add the test target with the first behaviour of the module.")
      })
  }

  static func commentViolations(in file: SourceFile) -> [Violation] {
    file.lines.filter { $0.remark == .plain }.map {
      Violation(
        file: file.path, line: $0.number, found: $0.text.trimmingCharacters(in: .whitespaces),
        fix: "Delete the comment. Say it with a name, a type or a smaller function. "
          + "Why a decision was made goes in the commit message. `///` is for what a declaration promises.")
    }
  }

  static func markerViolations(in file: SourceFile) -> [Violation] {
    file.lines.compactMap { line in
      guard let match = line.text.firstMatch(of: /\b(TODO|FIXME|HACK|XXX)\b/) else { return nil }
      return Violation(
        file: file.path, line: line.number, found: String(match.0),
        fix: "Finish it in this change, or leave it out and report it. Unfinished work is not merged.")
    }
  }
}
