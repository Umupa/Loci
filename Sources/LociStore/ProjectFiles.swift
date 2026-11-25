import Foundation
import LociModel

/// `projects/<id>/project.json` beside the data folder's other state: what only the app changes of a project.
/// The project's own files are under `agent/projects/<id>/`, as `home(.project(id))` gives them.
extension Store {
  static let projectsFolder = "projects"
  static let projectFile = "project.json"

  func projectFolder(_ id: Project.ID) -> URL {
    root.appending(path: "\(Self.projectsFolder)/\(id)", directoryHint: .isDirectory)
  }

  /// Every project that can be read, in the order they were started.
  public func projects() -> [Project] {
    subfolders(of: root.appending(path: Self.projectsFolder, directoryHint: .isDirectory))
      .compactMap { try? decodeJSON(Project.self, at: $0.appending(path: Self.projectFile)) }
      .sorted { ($0.createdAt, $0.id.description) < ($1.createdAt, $1.id.description) }
  }

  /// `notFound` when there is no such project, or it was deleted.
  public func project(_ id: Project.ID) throws -> Project {
    try decodeJSON(Project.self, at: projectFolder(id).appending(path: Self.projectFile))
  }

  /// Writes what the app keeps of the project; a new project gets its folders too.
  public func saveProject(_ project: Project) throws {
    try write(Formats.document(project), to: projectFolder(project.id).appending(path: Self.projectFile))
    try home(.project(project.id)).prepare()
  }

  /// Changes a project as it is on disk now.
  @discardableResult
  public func changeProject(_ id: Project.ID, _ change: (Project) -> Project) throws -> Project {
    let changed = change(try project(id))
    try write(Formats.document(changed), to: projectFolder(id).appending(path: Self.projectFile))
    return changed
  }
}

/// `.deleted/projects/<id>/`: a project deleted a moment ago, both its folders, kept until the deletion can
/// no longer be undone.
extension Store {
  private func deletedProject(_ id: Project.ID) -> URL {
    root.appending(path: "\(Self.setAsideFolder)/\(Self.projectsFolder)/\(id)", directoryHint: .isDirectory)
  }

  private static let agentPart = "agent"
  private static let statePart = "state"

  public func setAsideProjects() -> [Project.ID] {
    subfolders(of: root.appending(path: "\(Self.setAsideFolder)/\(Self.projectsFolder)", directoryHint: .isDirectory))
      .compactMap { EntityID(canonical: $0.lastPathComponent) }
  }

  public func setAsideProject(_ id: Project.ID) throws {
    let state = projectFolder(id)
    guard FileManager.default.fileExists(atPath: state.path(percentEncoded: false)) else {
      throw StoreError.notFound(id.description)
    }
    let place = deletedProject(id)
    try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
    try? home(.project(id)).setMemoryWritable(true)
    let agent = home(.project(id)).folder
    if FileManager.default.fileExists(atPath: agent.path(percentEncoded: false)) {
      try FileManager.default.moveItem(at: agent, to: place.appending(path: Self.agentPart))
    }
    try FileManager.default.moveItem(at: state, to: place.appending(path: Self.statePart))
  }

  public func restoreProject(_ id: Project.ID) throws {
    let place = deletedProject(id)
    let agent = place.appending(path: Self.agentPart)
    if FileManager.default.fileExists(atPath: agent.path(percentEncoded: false)) {
      let back = home(.project(id)).folder
      try FileManager.default.createDirectory(at: back.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.moveItem(at: agent, to: back)
    }
    let back = projectFolder(id)
    try FileManager.default.createDirectory(at: back.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: place.appending(path: Self.statePart), to: back)
    try FileManager.default.removeItem(at: place)
  }

  /// Gets rid of a project set aside for good, the way this store discards things.
  public func discardSetAsideProject(_ id: Project.ID) throws {
    let place = deletedProject(id)
    for folder in subfolders(of: place) { try discard(folder) }
    try discard(place)
  }
}
