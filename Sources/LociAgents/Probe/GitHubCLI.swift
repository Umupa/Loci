import Foundation
import LociModel

/// The `gh` signed in on this Mac: its token, which the app adds to GitHub's MCP calls, and the account.
public struct GitHubCLI: Sendable {
  private let launcher: any ProgramLauncher
  private let clock: any Clock<Duration>
  private let search: AgentSearch
  private let patience: Duration

  public init(
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock(),
    search: AgentSearch, patience: Duration = .seconds(10)
  ) {
    self.launcher = launcher
    self.clock = clock
    self.search = search
    self.patience = patience
  }

  /// `nil` when `gh` is not installed or not signed in.
  public func login() async -> GitHubLogin? {
    guard let gh = search.executable(named: ["gh"]) else { return nil }
    let token = await output(of: gh, ["auth", "token"]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty, !token.contains(where: \.isWhitespace) else { return nil }
    let account = await output(of: gh, ["api", "user", "--jq", ".login"]).trimmingCharacters(
      in: .whitespacesAndNewlines)
    return GitHubLogin(token: token, account: account.isEmpty || account.contains(" ") ? nil : account)
  }

  /// Runs `gh` with a command checked to only read, its arguments built again from what was checked, without
  /// a shell, in a folder it cannot change, and gives back what it printed.
  public func read(_ read: GitHubRead, within limit: Duration = .seconds(30)) async -> GitHubReply {
    guard let gh = search.executable(named: ["gh"]) else { return .failed("gh is not installed on this Mac") }
    let environment = ProcessInfo.processInfo.environment.merging([
      "GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1", "GH_PAGER": "cat", "NO_COLOR": "1",
    ]) { $1 }
    let invocation = Invocation(
      executable: gh, arguments: read.arguments, workingDirectory: URL.temporaryDirectory, environment: environment)
    guard let program = try? launcher.launch(invocation) else { return .failed("gh could not start") }
    program.closeInput()
    let reading = Task { () -> (Data, Data, Int32) in
      async let output = Self.collect(program.output)
      async let diagnostics = Self.collect(program.diagnostics)
      let (said, complained) = await (output, diagnostics)
      return (said, complained, await program.exit())
    }
    guard let (said, complained, status) = await OneShot.first(of: { await reading.value }, within: limit, clock: clock)
    else {
      program.terminate()
      return .failed("gh did not finish in \(limit.components.seconds) seconds")
    }
    guard status == 0 else {
      let why = String(decoding: complained, as: UTF8.self).split(separator: "\n").first.map(String.init)
      return .failed(why ?? "gh stopped with status \(status)")
    }
    let text = String(decoding: said.prefix(Self.longest), as: UTF8.self)
    return .output(said.count > Self.longest ? text + "\n…(cut at \(Self.longest / 1000) KB)" : text)
  }

  /// The most of `gh`'s output given back.
  static let longest = 200_000

  private static func collect(_ stream: AsyncStream<Data>) async -> Data {
    var data = Data()
    for await chunk in stream where data.count <= longest { data.append(chunk) }
    return data
  }

  private func output(of executable: URL, _ arguments: [String]) async -> String {
    await OneShot(launcher: launcher, clock: clock).output(
      Invocation(executable: executable, arguments: arguments, workingDirectory: URL.homeDirectory), within: patience)
      ?? ""
  }
}

/// What a `gh` command that reads came to.
public enum GitHubReply: Hashable, Sendable {
  case output(String)
  case failed(String)
}

/// What `gh auth token` and `gh api user` said.
public struct GitHubLogin: Hashable, Sendable {
  public let token: String
  public let account: String?

  public init(token: String, account: String?) {
    self.token = token
    self.account = account
  }
}
