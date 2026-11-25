import Foundation
import LociModel

/// The files of one home: the chat's are `agent/` itself, a project's `agent/projects/<id>/`. Each has its
/// own instructions, notes, index and wiki, panels, conversation copies and run records; what the companion
/// must not change is kept out of its reach, beside `settings.json` for the chat and in `projects/<id>/` for
/// a project. The soul, `USER.md`, the name, the picture and the feelings are the companion's own, on `Store`.
public struct HomeFiles: Sendable {
  public let home: Home
  let store: Store

  /// Where the home's sessions work.
  public var folder: URL {
    switch home {
    case .chat: store.agentFolder
    case .project(let id):
      store.agentFolder.appending(path: "\(Store.projectsFolder)/\(id)", directoryHint: .isDirectory)
    }
  }

  /// Where the app keeps the home's state, out of the companion's reach.
  var stateFolder: URL {
    switch home {
    case .chat: store.root
    case .project(let id): store.projectFolder(id)
    }
  }

  /// `sources/`: the data sources the home's panels read from.
  public var sources: DataSourceFolder { DataSourceFolder(home) }

  /// Makes the folders a session expects, and an empty index for a project.
  public func prepare() throws {
    for name in [Store.dayNotesFolder, Store.workspaceFolder, Store.conversationsFolder, Store.wikiFolder] {
      try FileManager.default.createDirectory(
        at: folder.appending(path: name, directoryHint: .isDirectory), withIntermediateDirectories: true)
    }
    let index = folder.appending(path: Store.memoryFile)
    if !FileManager.default.fileExists(atPath: index.path(percentEncoded: false)) {
      try store.write(Data("# Memory\n".utf8), to: index)
    }
  }

  /// `notes/<day>.md`, empty when nothing was noted that day.
  public func dayNotes(of day: Day) throws -> String {
    try store.optionalText(at: dayNotesFile(of: day)) ?? ""
  }

  public func dayNotesFile(of day: Day) -> URL {
    folder.appending(path: Store.dayNotesFolder).appending(path: "\(day).md")
  }

  /// `MEMORY.md`; empty when there is none.
  public func index() -> String {
    (try? store.optionalText(at: folder.appending(path: Store.memoryFile))) ?? ""
  }

  /// `AGENTS.md` as it is now; empty before it is written.
  public func instructions() -> String {
    (try? store.readText(folder.appending(path: Store.instructionsFile))) ?? ""
  }

  /// Writes `AGENTS.md`, and links `CLAUDE.md` to it unless the person put a file of their own there.
  public func writeInstructions(_ text: String) throws {
    try store.write(Data(text.utf8), to: folder.appending(path: Store.instructionsFile))
    let link = folder.appending(path: Store.claudeInstructionsFile).path(percentEncoded: false)
    let exists = (try? FileManager.default.attributesOfItem(atPath: link)) != nil
    if !exists {
      try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: Store.instructionsFile)
    }
  }

  /// Writes a skill where the agent programs that read skills find it: `.claude/skills/` for Claude Code
  /// and `.agents/skills/` for Codex.
  public func writeSkill(named name: String, _ text: String) throws {
    for skills in [".claude/skills", ".agents/skills"] {
      try store.write(Data(text.utf8), to: folder.appending(path: "\(skills)/\(name)/SKILL.md"))
    }
  }

  /// Where the record of a run of `home` started on `day` goes, relative to `agent/`.
  public static func runRecordPath(of run: Run.ID, on day: Day, in home: Home) -> String {
    home.folder + "\(Store.runsFolder)/\(day)/\(run).md"
  }

  /// A path relative to `agent/`, as the home's sessions see it from their own folder.
  public func local(_ path: String) -> String {
    path.hasPrefix(home.folder) ? String(path.dropFirst(home.folder.count)) : path
  }
}

extension Store {
  public func home(_ home: Home) -> HomeFiles {
    HomeFiles(home: home, store: self)
  }
}
