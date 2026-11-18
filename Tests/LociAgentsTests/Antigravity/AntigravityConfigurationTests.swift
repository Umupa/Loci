import Foundation
import Testing

@testable import LociAgents

struct AntigravityConfigurationTests {
  @Test(arguments: [false, true])
  func selectingAModelSkipsBooleanAndProviderOptions(selectorMissing: Bool) async throws {
    let folder = URL(filePath: "/agent")
    let fixture = selectorMissing ? "synthetic-model-selector-missing" : "synthetic-model-selector"
    let launcher = try ScriptedLauncher("Antigravity/\(fixture)", folder: folder)
    let driver = AcpDriver.antigravity(executable: URL(filePath: "/server/agy_acp_server.par"), launcher: launcher)
    let configuration = SessionConfiguration(workingDirectory: folder, model: "gemini-3.8-flash-low")
    if selectorMissing {
      await #expect(throws: AgentError.rejected("Antigravity did not advertise a model selector")) {
        _ = try await driver.open(configuration)
      }
    } else {
      let session = try await driver.open(configuration)
      await session.close()
    }
    launcher.verify()
  }
}
