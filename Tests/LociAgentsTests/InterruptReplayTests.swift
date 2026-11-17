import Foundation
import Testing

@testable import LociAgents

@Suite(.timeLimit(.minutes(1)))
struct InterruptReplayTests {
  enum AgentProtocol: String, CaseIterable, Sendable {
    case pi = "Pi"
    case acp = "Grok"
    case claudeCode = "ClaudeCode"
    case codex = "Codex"

    func driver(launcher: ScriptedLauncher, clock: any Clock<Duration>) -> any AgentDriver {
      let executable = URL(filePath: "/agent")
      switch self {
      case .pi:
        return PiDriver(executable: executable, launcher: launcher, clock: clock)
      case .acp:
        return AcpDriver(
          provider: .grok, executable: executable, arguments: { _ in [] }, launcher: launcher, clock: clock)
      case .claudeCode:
        return ClaudeCodeDriver(
          executable: executable, launcher: launcher, clock: clock, makeSessionID: { "session-1" })
      case .codex:
        return CodexDriver(executable: executable, launcher: launcher, clock: clock)
      }
    }
  }

  @Test(arguments: AgentProtocol.allCases, [false, true])
  func interruptingReturnsEvenWhenTheAgentNeverEndsTheTurn(agent: AgentProtocol, accepted: Bool) async throws {
    let folder = URL(filePath: "/synthetic")
    let launcher = try ScriptedLauncher(
      "\(agent.rawValue)/synthetic-interrupt-\(accepted ? "accepted" : "silent")",
      folder: folder, exitOnTermination: false)
    let session = try await agent.driver(launcher: launcher, clock: AcceleratedClock()).open(
      SessionConfiguration(workingDirectory: folder, permission: .full))
    let turn = try await session.send("Go on")
    let rescue = Task {
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      Issue.record("interrupt did not return at its deadline, even after terminate")
      await session.close()
    }
    async let concurrent: Void = session.interrupt()
    await session.interrupt()
    await concurrent
    rescue.cancel()
    #expect(launcher.terminations == 1)
    let events = await Scenario.watch(turn)
    #expect(events == [.ended(.interrupted)])
    await #expect(throws: AgentError.self) { try await session.send("Again") }
    await session.close()
    launcher.verify()
  }
}

/// Runs protocol deadlines a hundred times faster while preserving their order.
private struct AcceleratedClock: Clock {
  var now: ContinuousClock.Instant { .now }
  var minimumResolution: Duration { .zero }

  func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
    try await ContinuousClock().sleep(for: max(.zero, now.duration(to: deadline)) / 100)
  }
}
