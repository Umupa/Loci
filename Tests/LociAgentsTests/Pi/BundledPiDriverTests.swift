import Foundation
import LociModel
import Testing

@testable import LociAgents

struct BundledPiDriverTests {
  @Test func theBundledAndExternalPiNeverOpenEachOthersSessions() async throws {
    let launcher = ProbeLauncher()
    let executable = URL(filePath: "/pi")
    let folder = URL(filePath: "/work")
    let bundled = PiDriver.bundled(executable: executable, environment: [:], launcher: launcher)
    let system = PiDriver.pi(executable: executable, launcher: launcher)
    #expect(bundled.provider == .bundledPi)
    await #expect(throws: AgentError.sessionNotFound) {
      _ = try await bundled.open(
        SessionConfiguration(
          workingDirectory: folder, resume: SessionHandle(provider: .pi, value: "system")))
    }
    await #expect(throws: AgentError.sessionNotFound) {
      _ = try await system.open(
        SessionConfiguration(
          workingDirectory: folder, resume: SessionHandle(provider: .bundledPi, value: "bundled")))
    }
    #expect(launcher.launched.isEmpty)
  }
}
