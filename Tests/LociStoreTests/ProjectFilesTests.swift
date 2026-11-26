import Foundation
import LociModel
import Testing

@testable import LociStore

/// A project keeps its own files under `agent/projects/<id>/` and what only the app changes outside the
/// companion's reach; the chat's files stay where they always were.
struct ProjectFilesTests {
  static let id = Fixture.id(40)
  static let project = Project(id: id, name: "投资", summary: "盯纳指", createdAt: Fixture.instant)
  static let panel = Panel(name: "holdings", title: "持仓", follow: "x", body: .rows([.sentence("a")]))

  @Test func theChatsFilesAreWhereTheyWere() throws {
    try withStore { store in
      let chat = store.home(.chat)
      let day = try #require(Day("2026-11-25"))

      #expect(chat.folder == store.agentFolder)
      #expect(chat.stateFolder == store.root)
      #expect(chat.dayNotesFile(of: day) == store.agentFolder.appending(path: "notes/2026-11-25.md"))
      #expect(HomeFiles.runRecordPath(of: Self.id, on: day, in: .chat) == "runs/2026-11-25/\(Self.id).md")
    }
  }

  @Test func aProjectKeepsItsPanelsNotesAndMemoryInItsOwnFolder() throws {
    try withStore { store in
      try store.saveProject(Self.project)
      let files = store.home(.project(Self.id))
      try files.savePanel(Self.panel)

      #expect(files.folder == store.agentFolder.appending(path: "projects/\(Self.id)", directoryHint: .isDirectory))
      #expect(files.panels().map(\.name) == ["holdings"])
      #expect(store.home(.chat).panels().isEmpty)
      #expect(files.index() == "# Memory\n")
      #expect(FileManager.default.fileExists(atPath: files.folder.appending(path: "notes").path(percentEncoded: false)))
    }
  }

  @Test func whatOnlyTheAppChangesIsOutsideTheAgentFolder() throws {
    try withStore { store in
      try store.saveProject(Self.project)
      try store.home(.project(Self.id)).changePanelState { $0.order = [.panel("holdings")] }

      let project = store.root.appending(path: "projects/\(Self.id)/project.json")
      #expect(FileManager.default.fileExists(atPath: project.path(percentEncoded: false)))
      #expect(store.home(.project(Self.id)).panelState().order == [.panel("holdings")])
      #expect(store.home(.chat).panelState().order == [])
      #expect(try store.project(Self.id) == Self.project)
      #expect(store.projects() == [Self.project])
    }
  }

  @Test func aDeletedProjectComesBackWithEverything() throws {
    try withStore { store in
      try store.saveProject(Self.project)
      try store.home(.project(Self.id)).savePanel(Self.panel)
      try store.home(.project(Self.id)).setMemoryWritable(false)

      try store.setAsideProject(Self.id)

      #expect(store.projects().isEmpty)
      #expect(store.setAsideProjects() == [Self.id])
      #expect(throws: StoreError.self) { try store.project(Self.id) }

      try store.restoreProject(Self.id)

      #expect(store.projects() == [Self.project])
      #expect(store.home(.project(Self.id)).panels().map(\.name) == ["holdings"])
      #expect(store.setAsideProjects().isEmpty)
    }
  }

  @Test func discardingADeletedProjectRemovesBothItsFolders() throws {
    try withStore { store in
      try store.saveProject(Self.project)
      try store.home(.project(Self.id)).setMemoryWritable(false)
      try store.setAsideProject(Self.id)

      try store.discardSetAsideProject(Self.id)

      #expect(store.setAsideProjects().isEmpty)
      #expect(!FileManager.default.fileExists(atPath: store.home(.project(Self.id)).folder.path(percentEncoded: false)))
      #expect(store.projects().isEmpty)
    }
  }

  @Test func aProjectsTranscriptsAreFoundInItsHomeAndNeverFromTheChat() throws {
    try withStore { store in
      try store.saveProject(Self.project)
      let database = try StoreDatabase.inMemory()
      let run = HomeFiles.runRecordPath(of: Fixture.id(41), on: try #require(Day("2026-11-25")), in: .project(Self.id))
      try store.saveRunRecord("# run\n\n纳指回撤到二十日线。\n", at: run)

      try database.rebuild(from: store)

      #expect(run == "projects/\(Self.id)/runs/2026-11-25/\(Fixture.id(41)).md")
      #expect(try database.recall("二十日线").map(\.path) == [run])
      #expect(try database.recall("二十日线").first?.day == Day("2026-11-25"))
      #expect(try database.recall("二十日线", in: .project(Self.id)).map(\.path) == [run])
      #expect(try database.recall("二十日线", in: .chat).isEmpty)
      #expect(try database.recall("二十日线", in: .project(Fixture.id(42))).isEmpty)
    }
  }
}
