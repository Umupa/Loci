import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// DS-S1 in a project: a source saved with `loci source save` in a project's session is the project's, kept
/// in its folder and read by its panels; pinned to the chat, the panel reads the project's source still.
@Suite(.timeLimit(.minutes(1)))
struct ProjectSourceTests {
  @Test func aSourceSavedInAProjectsSessionIsTheProjects() async throws {
    let runner = FakeSources(records: ["513870": ["premium": .number(0.159)]])
    try await withHost(agent: FakeAgent(provider: .codex), sources: runner) { host, place, _ in
      let project = try await ProjectScenarioTests.start(host)
      let session = LocalSession.conversation(.project(project))
      let field = PanelNumber.field(SourceField("prem.513870.premium")!)

      _ = await Background.call(SavePanel(DataSourceScenarioTests.panel), from: session, on: host)
      _ = await Background.call(SaveDataSource(DataSourceScenarioTests.source), from: session, on: host)

      let folder = place.root.appending(path: "agent/projects/\(project)/sources/prem/source.json")
      #expect(FileManager.default.fileExists(atPath: folder.path()))
      #expect(!FileManager.default.fileExists(atPath: place.root.appending(path: "agent/sources/prem").path()))
      let column = try await host.panelColumn(of: .project(project))
      #expect(column.readings.number(field, of: .project(project)) == 0.159)
      #expect(try await host.run(ListDataSources(of: .project(project))).count == 1)
      #expect(try await host.run(ListDataSources()).isEmpty)

      _ = try await host.run(PinPanel("money", of: project, pinned: true))
      let chat = try await host.panelColumn(of: .chat)
      #expect(chat.readings.number(field, of: .project(project)) == 0.159)
      #expect(chat.readings.number(field, of: .chat) == nil)
    }
  }

  @Test func newNumbersInAProjectsChartPutTheDotOnItsSeal() async throws {
    let runner = FakeSources(records: ["513870": ["premium": .number(0.159)]])
    try await withHost(agent: FakeAgent(provider: .codex), sources: runner) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      let session = LocalSession.conversation(.project(project))
      _ = await Background.call(SavePanel(DataSourceScenarioTests.panel), from: session, on: host)
      _ = await Background.call(SaveDataSource(DataSourceScenarioTests.source), from: session, on: host)
      world.advance(minutes: 1)
      _ = try await host.run(SeeProject(project))
      #expect(try await host.projectBar().unseen.isEmpty)

      runner.set(["513870": ["premium": .number(0.2)]])
      world.advance(minutes: 1)
      #expect(await SourceLineTests.look(host) == 1)

      #expect(await ProjectScenarioTests.bar(host) { $0.unseen.contains(project) } != nil)
    }
  }

  @Test func aDeletedProjectsSourcesGoWithIt() async throws {
    let runner = FakeSources(records: ["513870": ["premium": .number(0.159)]])
    try await withHost(agent: FakeAgent(provider: .codex), sources: runner) { host, _, _ in
      let project = try await ProjectScenarioTests.start(host)
      let other = try await ProjectScenarioTests.start(host, named: "旅行")
      let session = LocalSession.conversation(.project(project))
      _ = await Background.call(SaveDataSource(DataSourceScenarioTests.source), from: session, on: host)
      let key = SourceKey(.project(project), "prem")
      #expect(try host.database.sourceSnapshot(key) != nil)

      _ = try await host.run(DeleteProject(project))
      _ = try await host.run(DeleteProject(other))

      #expect(try host.database.sourceSnapshot(key) == nil)
    }
  }
}
