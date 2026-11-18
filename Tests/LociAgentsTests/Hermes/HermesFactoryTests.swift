import Foundation
import Testing

@testable import LociAgents

struct HermesFactoryTests {
  @Test func additionalArgumentsFollowTheACPSubcommand() async {
    let driver = AcpDriver.hermes(
      executable: URL(filePath: "/hermes"), arguments: ["--verbose"], launcher: LaunchCheck())
    await #expect(throws: AgentError.cannotLaunch("Captured")) {
      _ = try await driver.open(.init(workingDirectory: URL(filePath: "/agent")))
    }
  }

  private struct LaunchCheck: ProgramLauncher {
    func launch(_ invocation: Invocation) throws(AgentError) -> RunningProgram {
      #expect(invocation.arguments == ["acp", "--verbose"])
      throw .cannotLaunch("Captured")
    }
  }
}
