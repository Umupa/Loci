import Foundation
import Testing

@testable import LociAgents

/// The only tests that start real programs, and only ones every Mac has: this layer is the bridge from
/// pipes to streams, and a recording cannot stand in for it.
struct SystemLauncherTests {
  private func launch(_ path: String, _ arguments: [String] = []) throws -> RunningProgram {
    try SystemLauncher().launch(
      Invocation(
        executable: URL(filePath: path), arguments: arguments, workingDirectory: URL(filePath: NSTemporaryDirectory())))
  }

  private func text(_ stream: AsyncStream<Data>) async -> String {
    var all = Data()
    for await chunk in stream { all.append(chunk) }
    return String(decoding: all, as: UTF8.self)
  }

  @Test func whatIsWrittenComesBackAndClosingInputEndsTheProgram() async throws {
    let cat = try launch("/bin/cat")
    try cat.write(Data("one\n".utf8))
    try cat.write(Data("two\n".utf8))
    cat.closeInput()
    #expect(await text(cat.output) == "one\ntwo\n")
    #expect(await cat.exit() == 0)
  }

  @Test func theExitStatusAndStandardErrorAreReported() async throws {
    let shell = try launch("/bin/sh", ["-c", "echo out; echo oops >&2; exit 3"])
    #expect(await text(shell.output) == "out\n")
    #expect(await text(shell.diagnostics) == "oops\n")
    #expect(await shell.exit() == 3)
  }

  @Test func outputWrittenJustBeforeExitIsNotLost() async throws {
    let shell = try launch("/bin/sh", ["-c", "i=0; while [ $i -lt 2000 ]; do echo line-$i; i=$((i+1)); done"])
    #expect(await text(shell.output).split(separator: "\n").count == 2000)
    #expect(await shell.exit() == 0)
  }

  @Test func aRunningProgramCanBeTerminated() async throws {
    let cat = try launch("/bin/cat")
    cat.terminate()
    #expect(await cat.exit() == SIGTERM)
    #expect(await text(cat.output).isEmpty)
  }

  @Test func writingToAProgramThatHasEndedThrowsInsteadOfKillingUs() async throws {
    let shell = try launch("/bin/sh", ["-c", "exit 0"])
    _ = await shell.exit()
    _ = await text(shell.output)
    #expect(throws: (any Error).self) {
      for _ in 0..<64 { try shell.write(Data(repeating: 0x61, count: 4096)) }
    }
  }

  @Test func theProgramInheritsOurEnvironmentUnlessGivenItsOwn() async throws {
    let shell = try launch("/bin/sh", ["-c", "printf %s \"$PATH\""])
    #expect(await text(shell.output) == ProcessInfo.processInfo.environment["PATH"])
  }

  @Test func aMissingProgramCannotLaunch() {
    #expect(throws: AgentError.self) { try launch("/nonexistent/program") }
  }

  @Test func theProgramRunsInTheGivenFolderWithTheGivenEnvironment() async throws {
    let shell = try SystemLauncher().launch(
      Invocation(
        executable: URL(filePath: "/bin/sh"), arguments: ["-c", "pwd; echo $LOCI_TEST"],
        workingDirectory: URL(filePath: "/usr"), environment: ["LOCI_TEST": "set"]))
    #expect(await text(shell.output) == "/usr\nset\n")
  }
}
