import Foundation
import Synchronization
import Testing

@testable import LociAgents

struct OpenCodeDriverTests {
  private final class CapturingLauncher: ProgramLauncher {
    let invocations = Mutex<[Invocation]>([])

    func launch(_ invocation: Invocation) throws(AgentError) -> RunningProgram {
      invocations.withLock { $0.append(invocation) }
      throw .cannotLaunch("Captured")
    }
  }

  @Test func openingUsesACPInTheMentorsDirectoryAndPreservesItsEnvironment() async {
    let launcher = CapturingLauncher()
    let driver = OpenCodeDriver(
      executable: URL(filePath: "/opencode"), arguments: ["--print-logs"],
      environment: ["PATH": "/bin", "OPENCODE_PERMISSION": #"{"*":"allow"}"#], launcher: launcher)
    let folder = URL(filePath: "/mentor")
    await #expect(throws: AgentError.cannotLaunch("Captured")) {
      _ = try await driver.open(.init(workingDirectory: folder, permission: .ask))
    }
    let invocation = launcher.invocations.withLock { $0.first }
    #expect(invocation?.executable == URL(filePath: "/opencode"))
    #expect(invocation?.arguments == ["acp", "--print-logs"])
    #expect(invocation?.workingDirectory == folder)
    #expect(invocation?.environment == ["PATH": "/bin", "OPENCODE_PERMISSION": #"{"*":"ask"}"#])
  }

  @Test func fullAccessSetsOpenCodesDefaultPermissionToAllow() async {
    let launcher = CapturingLauncher()
    let driver = OpenCodeDriver(executable: URL(filePath: "/opencode"), environment: [:], launcher: launcher)
    await #expect(throws: AgentError.cannotLaunch("Captured")) {
      _ = try await driver.open(.init(workingDirectory: URL(filePath: "/mentor"), permission: .full))
    }
    #expect(launcher.invocations.withLock { $0.first?.environment?["OPENCODE_PERMISSION"] } == #"{"*":"allow"}"#)
  }

  @Test func aHandleFromAnotherProviderIsRejectedBeforeLaunching() async {
    let launcher = CapturingLauncher()
    let driver = OpenCodeDriver(executable: URL(filePath: "/opencode"), launcher: launcher)
    await #expect(throws: AgentError.sessionNotFound) {
      _ = try await driver.open(
        .init(
          workingDirectory: URL(filePath: "/mentor"), permission: .full, resume: .init(provider: .pi, value: "old")))
    }
    #expect(launcher.invocations.withLock { $0.isEmpty })
  }
}
