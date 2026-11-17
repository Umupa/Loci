import Foundation
import Testing

@testable import LociAgents

@Suite(.timeLimit(.minutes(1)))
struct ProgramConnectionTests {
  enum Wire: CaseIterable, Sendable {
    case pi, acp, claudeCode, codex
  }

  private struct BrokenInput: LocalizedError {
    var errorDescription: String? { "Input closed" }
  }

  @Test(arguments: Wire.allCases)
  func aRequestFailsAtOnceWhenWritingFails(wire: Wire) async {
    let pipes = Pipes()
    let program = pipes.program { _ in throw BrokenInput() }
    let start = ContinuousClock.now
    await #expect(throws: AgentError.rejected("Input closed")) {
      switch wire {
      case .pi:
        _ = try await PiChannel(program: program, clock: ContinuousClock()).request(.getState, within: .seconds(5))
      case .acp:
        _ = try await AcpChannel(program: program, clock: ContinuousClock()).request(
          "initialize", .null, within: .seconds(5))
      case .claudeCode:
        _ = try await ClaudeCodeChannel(program: program, clock: ContinuousClock()).request(
          .control("initialize"), within: .seconds(5))
      case .codex:
        _ = try await CodexChannel(program: program, clock: ContinuousClock()).request(
          "initialize", params: .null, within: .seconds(5))
      }
    }
    #expect(ContinuousClock.now - start < .seconds(1))
    pipes.end()
  }

  @Test(arguments: Wire.allCases)
  func aRecordWithoutAResponseAlsoReportsWritingFailure(wire: Wire) async {
    let pipes = Pipes()
    let program = pipes.program { _ in throw BrokenInput() }
    await #expect(throws: AgentError.rejected("Input closed")) {
      switch wire {
      case .pi: try await PiChannel(program: program, clock: ContinuousClock()).send(.abort)
      case .acp: try await AcpChannel(program: program, clock: ContinuousClock()).notify("session/cancel", .null)
      case .claudeCode: try await ClaudeCodeChannel(program: program, clock: ContinuousClock()).send(.prompt("Go"))
      case .codex: try await CodexChannel(program: program, clock: ContinuousClock()).send(.null)
      }
    }
    pipes.end()
  }

  @Test func aResponseWrittenJustBeforeExitResolvesBeforeTheConnectionEnds() async throws {
    let pipes = Pipes()
    let connection = ProgramConnection(
      program: pipes.program { _ in
        pipes.output.yield(Data("po".utf8))
        pipes.output.yield(Data("ng\r\n".utf8))
        pipes.end()
      }, clock: ContinuousClock())
    let listening = Task {
      await connection.listen { line in
        await connection.resolve("1", .success(.string(String(decoding: line, as: UTF8.self))))
      }
    }
    let result = try await connection.request("1", data: Data(), operation: "ping", within: .seconds(5))
    #expect(result == .string("pong"))
    #expect(await listening.value == .exited(code: 0, diagnostics: ""))
  }

  @Test func onlyTheLastTwoThousandBytesOfDiagnosticsAreReported() async {
    let pipes = Pipes()
    let connection = ProgramConnection(program: pipes.program { _ in }, clock: ContinuousClock())
    pipes.diagnostics.yield(Data(repeating: 0x78, count: 2500))
    pipes.diagnostics.yield(Data("\n fatal \n".utf8))
    pipes.end(code: 9)
    let reason = await connection.listen { _ in }
    #expect(reason == .exited(code: 9, diagnostics: String(repeating: "x", count: 1991) + "\n fatal"))
  }

  @Test func exitEndsTheConnectionEvenWhenAChildKeepsThePipesOpen() async {
    let pipes = Pipes()
    let connection = ProgramConnection(program: pipes.program { _ in }, clock: ImpatientClock())
    pipes.exits.yield(7)
    pipes.exits.finish()
    #expect(await connection.listen { _ in } == .exited(code: 7, diagnostics: ""))
    pipes.end()
  }

  @Test func aTimedOutRequestDoesNotPreventTheNextResponseFromArriving() async throws {
    let pipes = Pipes()
    let connection = ProgramConnection(
      program: pipes.program { data in
        if !data.isEmpty { pipes.output.yield(Data("pong\n".utf8)) }
      }, clock: ContinuousClock())
    let listening = Task {
      await connection.listen { _ in await connection.resolve("2", .success(.string("pong"))) }
    }
    await #expect(throws: AgentError.unresponsive("ping")) {
      try await connection.request("1", data: Data(), operation: "ping", within: .zero)
    }
    let result = try await connection.request("2", data: Data([1]), operation: "ping", within: .seconds(5))
    #expect(result == .string("pong"))
    await connection.shutDown(patience: .seconds(5))
    #expect(await listening.value == .exited(code: 0, diagnostics: ""))
  }

  @Test func exitFailsAPendingRequestWithTheProgramsDiagnostics() async {
    let pipes = Pipes()
    let connection = ProgramConnection(
      program: pipes.program { _ in
        pipes.diagnostics.yield(Data("failed\n".utf8))
        pipes.end(code: 9)
      }, clock: ContinuousClock())
    let listening = Task { await connection.listen { _ in } }
    let failure = AgentError.exited(code: 9, diagnostics: "failed")
    await #expect(throws: failure) {
      try await connection.request("1", data: Data(), operation: "ping", within: .seconds(5))
    }
    #expect(await listening.value == failure)
  }

  @Test func shuttingDownTerminatesAProgramThatIgnoresClosingInput() async {
    let pipes = Pipes()
    let program = pipes.program { _ in }
    let stubborn = RunningProgram(
      output: program.output, diagnostics: program.diagnostics, write: program.write, closeInput: {},
      terminate: { pipes.end(code: 15) }, exit: program.exit)
    let connection = ProgramConnection(program: stubborn, clock: ImpatientClock())
    let listening = Task { await connection.listen { _ in } }
    await connection.shutDown(patience: .seconds(3))
    #expect(await listening.value == .exited(code: 15, diagnostics: ""))
  }

  private struct Pipes: Sendable {
    let output: AsyncStream<Data>.Continuation
    let diagnostics: AsyncStream<Data>.Continuation
    let exits: AsyncStream<Int32>.Continuation
    private let stdout: AsyncStream<Data>
    private let stderr: AsyncStream<Data>
    private let status: Task<Int32, Never>

    init() {
      (stdout, output) = AsyncStream.makeStream(of: Data.self)
      (stderr, diagnostics) = AsyncStream.makeStream(of: Data.self)
      let (codes, exits) = AsyncStream.makeStream(of: Int32.self)
      self.exits = exits
      status = Task {
        for await code in codes { return code }
        return -1
      }
    }

    func program(write: @escaping @Sendable (Data) throws -> Void) -> RunningProgram {
      RunningProgram(
        output: stdout, diagnostics: stderr, write: write, closeInput: { end() }, terminate: { end() },
        exit: { await status.value })
    }

    func end(code: Int32 = 0) {
      output.finish()
      diagnostics.finish()
      exits.yield(code)
      exits.finish()
    }
  }
}
