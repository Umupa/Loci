import Foundation
import Synchronization
import Testing

@testable import LociAgents

/// Stands in for Pi by replaying a recording: it says what Pi said, and waits wherever the driver
/// wrote something until the driver writes the same thing again.
final class ScriptedLauncher: ProgramLauncher {
  private struct State {
    var steps: [Step]
    var problems: [String] = []
    var output: AsyncStream<Data>.Continuation?
    var diagnostics: AsyncStream<Data>.Continuation?
    var exits: AsyncStream<Int32>.Continuation?
  }

  private let folder: URL
  private let state: Mutex<State>

  init(_ fixture: String, folder: URL) throws {
    self.folder = folder
    self.state = Mutex(State(steps: try Recording.load(fixture)))
  }

  func launch(_ invocation: Invocation) throws(AgentError) -> RunningProgram {
    let (output, outputContinuation) = AsyncStream.makeStream(of: Data.self)
    let (diagnostics, diagnosticsContinuation) = AsyncStream.makeStream(of: Data.self)
    let (exits, exitsContinuation) = AsyncStream.makeStream(of: Int32.self)
    let status = Task {
      for await code in exits { return code }
      return Int32(-1)
    }
    state.withLock { state in
      state.output = outputContinuation
      state.diagnostics = diagnosticsContinuation
      state.exits = exitsContinuation
      expect(.launch(Recording.portable(invocation.arguments, folder: folder)), in: &state)
    }
    return RunningProgram(
      output: output, diagnostics: diagnostics,
      write: { data in
        self.state.withLock { state in
          let portable = Data(String(decoding: data, as: UTF8.self).replacing(self.folder.path, with: "$FOLDER").utf8)
          for record in Recording.records(in: portable) { self.expect(.to(record), in: &state) }
        }
      },
      closeInput: { self.state.withLock { self.expect(.close, in: &$0) } },
      terminate: { self.state.withLock { self.end(15, "", in: &$0) } },
      exit: { await status.value })
  }

  /// Fails the test if the driver said anything the recording does not have, or left part of it unplayed.
  func verify() {
    let (problems, left) = state.withLock { ($0.problems, $0.steps.count) }
    #expect(problems == [])
    #expect(left == 0, "the recording has \(left) steps the driver never reached")
  }

  /// Checks one thing the driver did against the recording. Where the recording has the driver writing
  /// several records in a row, they may come in any order: Pi said nothing in between to order them by.
  private func expect(_ step: Step, in state: inout State) {
    let writes = state.steps.prefix { if case .to = $0 { true } else { false } }
    if state.steps.first == step {
      state.steps.removeFirst()
    } else if let index = writes.firstIndex(of: step) {
      state.steps.remove(at: index)
    } else if step == .close, state.output == nil {
      return
    } else {
      let wanted = state.steps.first.map { Recording.line($0.json) } ?? "nothing more"
      state.problems.append("driver did \(Recording.line(step.json)), recording has \(wanted)")
      if step == .close { end(0, "", in: &state) }
    }
    play(&state)
  }

  private func play(_ state: inout State) {
    while let next = state.steps.first {
      switch next {
      case .from(let record):
        state.output?.yield(Data((Recording.line(record) + "\n").utf8))
      case .exit(let code, let said):
        end(code, said, in: &state)
      case .launch, .to, .close:
        return
      }
      state.steps.removeFirst()
    }
  }

  private func end(_ code: Int32, _ said: String, in state: inout State) {
    if !said.isEmpty { state.diagnostics?.yield(Data(said.utf8)) }
    state.output?.finish()
    state.diagnostics?.finish()
    state.exits?.yield(code)
    state.exits?.finish()
    (state.output, state.diagnostics, state.exits) = (nil, nil, nil)
  }
}
