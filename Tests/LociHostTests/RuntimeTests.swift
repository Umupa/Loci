import Foundation
import LociModel
import Testing

@testable import LociHost

/// L-S6: what Loci runs on is one setting for the whole app.
@Suite(.timeLimit(.minutes(1)))
struct RuntimeTests {
  @Test func theSettingsSeeWhichAgentsAreInstalled() async throws {
    try await withHost { host, _, world in
      let found = try await host.run(DetectAgents())
      _ = try await host.run(DetectAgents(again: true))

      #expect(found == TestWorld.installed)
      #expect(world.lookedAgain == [false, true])
    }
  }

  @Test func withNothingChosenLociRunsOnWhatTheHostStartedWith() async throws {
    try await withHost { host, _, _ in
      let runtime = try await host.run(ReadRuntime())

      #expect(runtime == Runtime(provider: .pi))
    }
  }

  @Test func aChosenRuntimeIsKeptAndAnnounced() async throws {
    try await withHost { host, _, _ in
      let feed = host.subscribe(CurrentRuntime())

      _ = try await host.run(SetRuntime(Runtime(provider: .codex, model: "gpt-5", effort: .high)))

      #expect(await value(feed) { $0.provider == .codex } == Runtime(provider: .codex, model: "gpt-5", effort: .high))
      #expect(try await host.run(ReadRuntime()) == Runtime(provider: .codex, model: "gpt-5", effort: .high))
    }
  }

  @Test func theNextTurnRunsWithTheChosenModelAndEffort() async throws {
    try await withHost { host, _, world in
      _ = try await host.run(SetRuntime(Runtime(provider: .pi, model: "deepseek", effort: .minimal)))

      _ = try await host.run(SendMessage(to: .main, text: "Hi"))
      _ = try #require(await settled(host))

      #expect(world.agent.opened.last?.model == "deepseek")
      #expect(world.agent.opened.last?.effort == .minimal)
    }
  }

  @Test func theDataLocationIsTheHostsFolder() async throws {
    try await withHost { host, place, _ in
      let location = try await host.run(DataLocation())

      #expect(location == HostPath(place.root))
      #expect(await host.localFile(.dataFolder) == LocalFile(place.root))
    }
  }
}
