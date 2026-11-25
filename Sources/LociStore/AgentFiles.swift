import Foundation
import LociModel

/// `agent/`: Loci's soul, what it remembers, its notes and diary, its picture, and the instructions every
/// session starts from. Loci and the person both write these files; the app only reads them, except where
/// the person edits through the app.
extension Store {
  static let agentFolderName = "agent"
  static let soulFile = "SOUL.md"
  static let profileFile = "USER.md"
  static let memoryFile = "MEMORY.md"
  static let instructionsFile = "AGENTS.md"
  /// Claude Code reads its own name rather than `AGENTS.md`, so it is given a link to the same file.
  static let claudeInstructionsFile = "CLAUDE.md"
  static let dayNotesFolder = "notes"
  static let diaryFolder = "diary"
  static let workspaceFolder = "workspace"
  static let avatarName = "avatar"

  /// Gives the companion its first files and updates an older default soul while preserving the person's edits.
  public func prepareAgent(soul: String, replacing previous: String? = nil) throws {
    for folder in [
      Self.dayNotesFolder, Self.diaryFolder, Self.workspaceFolder, Self.conversationsFolder, Self.wikiFolder,
    ] {
      try FileManager.default.createDirectory(
        at: agentFolder.appending(path: folder, directoryHint: .isDirectory), withIntermediateDirectories: true)
    }
    let core = Soul(parsing: soul).core
    let previousCore = previous.map { Soul(parsing: $0).core }
    if let saved = try? agentText(.soul) {
      let savedCore = Soul(parsing: saved).core
      let named = "# Soul\n\nYou are Loci. You live on this Mac"
      let unnamed = "# Soul\n\nYou live on this Mac"
      let stock = savedCore.hasPrefix(named) ? unnamed + savedCore.dropFirst(named.count) : savedCore
      if savedCore != core, stock == core || stock == previousCore {
        try saveAgentText(Soul.rewriting(saved, core: core), as: .soul)
      }
    }
    let starts = [(Self.soulFile, soul), (Self.profileFile, "# User\n"), (Self.memoryFile, "# Memory\n")]
    for (name, text) in starts {
      let url = agentFolder.appending(path: name)
      if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
        try write(Data(text.utf8), to: url)
      }
    }
  }

  public func companionName() throws -> String {
    Self.normalizedName(try agentText(.displayName))
  }

  public func saveCompanionName(_ name: String) throws {
    try saveAgentText(Self.normalizedName(name), as: .displayName)
  }

  private static func normalizedName(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  /// The text of `NAME.txt`, `SOUL.md`, `USER.md` or `MEMORY.md`; empty when the file is missing.
  public func agentText(_ file: AgentFile) throws -> String {
    do {
      return try readText(agentFolder.appending(path: file.name))
    } catch StoreError.notFound {
      return ""
    }
  }

  /// Writes the file; the index stays read-only around the write when it was.
  public func saveAgentText(_ text: String, as file: AgentFile) throws {
    let url = agentFolder.appending(path: file.name)
    guard file == .memory else { return try write(Data(text.utf8), to: url) }
    try home(.chat).writingMemory { try write(Data(text.utf8), to: url) }
  }

  /// `diary/<day>.md`; `notFound` when Loci wrote none that day.
  public func diary(of day: Day) throws -> String {
    try readText(diaryFile(of: day))
  }

  public func diaryFile(of day: Day) -> URL {
    agentFolder.appending(path: Self.diaryFolder).appending(path: "\(day).md")
  }

  /// The days Loci wrote a diary for, newest first.
  public func diaryDays() -> [Day] {
    files(in: agentFolder.appending(path: Self.diaryFolder), withExtension: "md")
      .compactMap { Day($0.deletingPathExtension().lastPathComponent) }.sorted(by: >)
  }

  /// The picture the person chose; `nil` when they chose none.
  public func avatar() throws -> Avatar? {
    guard let url = avatarFiles().first else { return nil }
    do {
      return try Avatar(data: try read(url), format: url.pathExtension)
    } catch let error as ModelError {
      throw StoreError.invalid(FileProblem(path: relativePath(of: url), kind: .invalid, reason: error.description))
    }
  }

  /// Keeps the picture as `avatar.<format>` in place of any other.
  public func setAvatar(_ avatar: Avatar) throws {
    let url = agentFolder.appending(path: "\(Self.avatarName).\(avatar.format)")
    try write(avatar.data, to: url)
    for other in avatarFiles() where other.lastPathComponent != url.lastPathComponent {
      try FileManager.default.removeItem(at: other)
    }
  }

  public func resetAvatar() throws {
    for file in avatarFiles() { try FileManager.default.removeItem(at: file) }
  }

  private func avatarFiles() -> [URL] {
    Avatar.formats.sorted().map { agentFolder.appending(path: "\(Self.avatarName).\($0)") }
      .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
  }

  func optionalText(at url: URL) throws -> String? {
    do {
      return try readText(url)
    } catch StoreError.notFound {
      return nil
    }
  }
}

/// The editable files describing the companion and what it knows.
public enum AgentFile: Sendable {
  case displayName
  case soul
  case profile
  case memory

  var name: String {
    switch self {
    case .displayName: "NAME.txt"
    case .soul: Store.soulFile
    case .profile: Store.profileFile
    case .memory: Store.memoryFile
    }
  }
}
