import Foundation
import LociMedia
import Synchronization
import Testing

/// Answers in place of programs, and remembers what it was asked to run.
final class ScriptedRunner: ProgramRunner {
  typealias Answer = @Sendable (ProgramCall) -> (lines: [String], result: ProgramResult)
  private let answer: Answer
  private let asked = Mutex<[ProgramCall]>([])

  init(_ answer: @escaping Answer) {
    self.answer = answer
  }

  convenience init(output: String = "", status: Int32 = 0, diagnostics: String = "") {
    self.init { _ in ([], ProgramResult(status: status, output: output, diagnostics: diagnostics)) }
  }

  var calls: [ProgramCall] { asked.withLock { $0 } }

  func run(_ call: ProgramCall, line: @escaping @Sendable (String) -> Void) async throws(ProgramError) -> ProgramResult
  {
    asked.withLock { $0.append(call) }
    let (lines, result) = answer(call)
    for each in lines { line(each) }
    return result
  }
}

enum Fixture {
  static func data(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
  }
}
