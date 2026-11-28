import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// WT-S2, WT-S12: the chat's and each project's `WATCH.md` are read and written through the host, and follow
/// the file as the companion or the person changes it outside the app.
@Suite(.timeLimit(.minutes(1)))
struct WatchNotesTests {
  @Test func whatIsSavedIsReadBackInItsOwnHomeOnly() async throws {
    try await withHost { host, place, _ in
      let project = try await ProjectScenarioTests.start(host)

      _ = try await host.run(SaveWatch("- 稳市政策要告诉我\n", in: .project(project)))

      #expect(try await host.watch(of: .project(project)) == "- 稳市政策要告诉我\n")
      #expect(try await host.watch(of: .chat) == "# Watch\n")
      let file = place.root.appending(path: "agent/projects/\(project)/WATCH.md")
      #expect(try String(contentsOf: file, encoding: .utf8) == "- 稳市政策要告诉我\n")
    }
  }

  @Test func aProjectThatIsGoneHasNoWatch() async throws {
    try await withHost { host, _, _ in
      let gone = Home.project(EntityID(canonical: "019a8b3e-0000-7000-8000-000000000009")!)

      await #expect(throws: HostError.self) { try await host.watch(of: gone) }
      await #expect(throws: HostError.self) { try await host.run(SaveWatch("x", in: gone)) }
    }
  }

  @Test func theWatchFollowsTheFileWhenItIsChangedOutsideTheApp() async throws {
    try await withHost { host, place, _ in
      let project = try await ProjectScenarioTests.start(host)
      let chat = host.subscribe(WatchNotes(of: .chat))
      let projectFeed = host.subscribe(WatchNotes(of: .project(project)))
      _ = await value(chat) { _ in true }
      _ = await value(projectFeed) { _ in true }

      try place.edit(place.root.appending(path: "agent/WATCH.md")) { $0 + "- 主对话只看论文\n" }
      try place.edit(place.root.appending(path: "agent/projects/\(project)/WATCH.md")) { $0 + "- 龙虎榜是噪音\n" }

      #expect(await value(chat) { $0.contains("主对话只看论文") } != nil)
      #expect(await value(projectFeed) { $0.contains("龙虎榜是噪音") } != nil)
    }
  }

  @Test func whatIsSavedIsWhatTheNextBatchIsSortedWith() async throws {
    let model = TriageModel.discarding()
    let sources = FakeSources()
    try await withWatchHost(model: model, sources: sources) { host, _, world in
      _ = try await host.run(SaveDataSource(Watching.news))
      _ = try await host.run(SaveWatch("稳市政策要告诉我。\n", in: .chat))

      sources.set(entries: WatchScenarioTests.entries)
      await Watching.fetchNext(on: host, world)

      #expect(await model.inputs.map(\.watch) == ["稳市政策要告诉我。\n"])
    }
  }
}
