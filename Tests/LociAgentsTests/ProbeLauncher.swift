import Foundation
import Synchronization

@testable import LociAgents

/// Answers for the programs a probe starts, without starting anything.
final class ProbeLauncher: ProgramLauncher {
  struct Answer: Sendable {
    var output: String = ""
    var status: Int32 = 0
    /// Whether the program ends on its own, or waits until it is terminated.
    var ends = true
  }

  private struct State {
    var answers: [String: Answer]
    var launched: [String] = []
  }

  private let state: Mutex<State>

  init(_ answers: [String: Answer] = [:]) {
    state = Mutex(State(answers: answers))
  }

  /// The programs started so far, as `name arguments`; a program with no answer never starts.
  var launched: [String] {
    state.withLock { $0.launched }
  }

  static func key(_ invocation: Invocation) -> String {
    ([invocation.executable.lastPathComponent] + invocation.arguments).joined(separator: " ")
  }

  func launch(_ invocation: Invocation) throws(AgentError) -> RunningProgram {
    let key = Self.key(invocation)
    let answer = state.withLock { state -> Answer? in
      state.launched.append(key)
      return state.answers[key]
    }
    guard let answer else { throw .cannotLaunch(key) }

    let (output, outputWrites) = AsyncStream.makeStream(of: Data.self)
    let (diagnostics, diagnosticWrites) = AsyncStream.makeStream(of: Data.self)
    let (exits, exitWrites) = AsyncStream.makeStream(of: Int32.self)
    let status = Task {
      for await code in exits { return code }
      return Int32(-1)
    }
    let ended = Mutex(false)
    let end: @Sendable (Int32) -> Void = { code in
      let first = ended.withLock { ended in
        guard !ended else { return false }
        ended = true
        return true
      }
      guard first else { return }
      if !answer.output.isEmpty { outputWrites.yield(Data(answer.output.utf8)) }
      outputWrites.finish()
      diagnosticWrites.finish()
      exitWrites.yield(code)
      exitWrites.finish()
    }
    if answer.ends { end(answer.status) }

    return RunningProgram(
      output: output, diagnostics: diagnostics,
      write: { _ in },
      closeInput: {},
      terminate: { end(SIGTERM) },
      exit: { await status.value })
  }
}
