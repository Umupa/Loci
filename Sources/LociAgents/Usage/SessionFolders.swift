import Foundation
import LociModel

/// Where the CLIs keep their session files, and how the one Loci knows by a handle is found and read. Only
/// Claude Code and Codex keep files Loci can read.
public struct SessionFolders: Hashable, Sendable {
  /// Claude Code's `projects` folder: a folder per working directory, a file per session.
  public let claudeCode: URL?
  /// Codex's `sessions` folder: a folder per day, a file per thread.
  public let codex: URL?

  public init(claudeCode: URL?, codex: URL?) {
    self.claudeCode = claudeCode
    self.codex = codex
  }

  public static let none = SessionFolders(claudeCode: nil, codex: nil)

  /// The folders under `home`, or where `CLAUDE_CONFIG_DIR` and `CODEX_HOME` move them.
  public static func home(_ home: URL, environment: [String: String]) -> SessionFolders {
    let claude = environment["CLAUDE_CONFIG_DIR"].map { URL(filePath: $0) } ?? home.appending(path: ".claude")
    let codex = environment["CODEX_HOME"].map { URL(filePath: $0) } ?? home.appending(path: ".codex")
    return SessionFolders(claudeCode: claude.appending(path: "projects"), codex: codex.appending(path: "sessions"))
  }

  /// Where the file of a session that started at `startedAt` may be, with Codex's day folders named in
  /// `timeZone`; `nil` for a CLI whose files Loci does not read.
  public func search(provider: Provider, handle: String, startedAt: Timestamp, timeZone: TimeZone)
    -> SessionFileSearch?
  {
    switch provider {
    case .claudeCode:
      return claudeCode.map { SessionFileSearch(folders: [$0], depth: 1, name: .equal("\(handle).jsonl")) }
    case .codex:
      guard let codex else { return nil }
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = timeZone
      let days = [-1, 0, 1].compactMap { calendar.date(byAdding: .day, value: $0, to: startedAt.date) }
      let folders = days.map { day in
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return codex.appending(
          path: String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
      }
      return SessionFileSearch(folders: folders, depth: 0, name: .suffix("-\(handle).jsonl"))
    case .pi, .bundledPi, .omp, .grok, .antigravity, .cursor, .fx, .hermes, .opencode:
      return nil
    }
  }

  /// Reads the text of a session file `provider` wrote.
  public static func sessionFile(of provider: Provider, text: String) -> SessionFile? {
    switch provider {
    case .claudeCode: SessionFile(claudeCode: text)
    case .codex: SessionFile(codex: text)
    case .pi, .bundledPi, .omp, .grok, .antigravity, .cursor, .fx, .hermes, .opencode: nil
    }
  }
}

/// Where to look for one session file: in these folders and the folders `depth` levels under them, for a file
/// whose name is as `name` says.
public struct SessionFileSearch: Hashable, Sendable {
  public let folders: [URL]
  public let depth: Int
  public let name: Name

  public enum Name: Hashable, Sendable {
    case equal(String)
    case suffix(String)

    public func matches(_ file: String) -> Bool {
      switch self {
      case .equal(let name): file == name
      case .suffix(let suffix): file.hasSuffix(suffix)
      }
    }
  }
}
