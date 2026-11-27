import Foundation

/// The folders agent programs are looked for in, most trusted first.
public struct AgentSearch: Hashable, Sendable {
  public let directories: [URL]

  public init(directories: [URL]) {
    self.directories = directories
  }

  /// The program under one of `names`, from the first folder that has one.
  func executable(named names: [String]) -> URL? {
    for directory in directories {
      for name in names {
        let candidate = directory.appending(path: name)
        if Self.isExecutable(candidate) { return candidate }
      }
    }
    return nil
  }

  /// Whether a program under one of `names` is there but cannot be run: it is not executable, or the system
  /// would not even let Loci look at it.
  func isBlocked(named names: [String]) -> Bool {
    directories.contains { directory in
      names.contains { name in
        let candidate = directory.appending(path: name)
        return SystemLauncher.isThere(candidate) && !Self.isExecutable(candidate)
      }
    }
  }

  /// Where a program can be on this Mac: the login shell's PATH, the PATH this process inherited, then the
  /// folders the installers use that a window opened from Finder never hears about.
  public static func forThisMac(
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock(),
    environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = URL.homeDirectory,
    patience: Duration = .seconds(5)
  ) async -> AgentSearch {
    let loginPath = await LoginShell.path(
      launcher: launcher, clock: clock, environment: environment, home: home, patience: patience)
    return AgentSearch(
      directories: directories(loginPath: loginPath, inheritedPath: environment["PATH"], home: home))
  }

  static func directories(loginPath: String?, inheritedPath: String?, home: URL) -> [URL] {
    let listed = [loginPath, inheritedPath].compactMap { $0 }.flatMap { path in
      path.split(separator: ":").filter { !$0.isEmpty }.map { URL(filePath: String($0), directoryHint: .isDirectory) }
    }
    return unique(listed + installerFolders(home))
  }

  static func installerFolders(_ home: URL) -> [URL] {
    let perUser = [
      ".local/bin", ".local/share/claude", ".claude/local", ".cargo/bin", ".bun/bin", ".npm-global/bin",
      ".opencode/bin", ".fx/bin", ".grok/bin", ".hermes/hermes-agent/venv/bin", ".hermes/hermes-agent/.venv/bin",
      "n/bin",
    ]
    let shared = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/snap/bin"]
    return perUser.map { home.appending(path: $0) } + shared.map { URL(filePath: $0, directoryHint: .isDirectory) }
  }

  private static func unique(_ directories: [URL]) -> [URL] {
    var seen: Set<URL> = []
    return directories.filter { seen.insert($0).inserted }
  }

  private static func isExecutable(_ path: URL) -> Bool {
    guard
      let values = try? path.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey])
    else { return false }
    return values.isRegularFile == true && values.isExecutable == true
  }
}

/// The environment the person's own terminal has, read by asking their login shell for it.
enum LoginShell {
  /// The PATH out of `printenv`. Interactive (`-i`) as well as login (`-l`) because version managers set
  /// themselves up in `.zshrc` only, and every CLI they installed looks missing without it.
  static func path(
    launcher: any ProgramLauncher, clock: any Clock<Duration>, environment: [String: String], home: URL,
    patience: Duration
  ) async -> String? {
    let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
    let said = await OneShot(launcher: launcher, clock: clock).output(
      Invocation(
        executable: URL(filePath: shell), arguments: ["-lic", "printenv"], workingDirectory: home,
        environment: environment),
      within: patience)
    return said?.split(separator: "\n").last { $0.hasPrefix("PATH=") }.map { String($0.dropFirst(5)) }
  }
}
