import Foundation
import LociModel

/// Asks an agent program which models it can run, in the names its `--model` takes.
public struct ModelList: Sendable {
  private let launcher: any ProgramLauncher
  private let clock: any Clock<Duration>
  private let search: AgentSearch
  private let workingDirectory: URL
  private let patience: Duration

  public init(
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock(),
    search: AgentSearch, workingDirectory: URL = URL.homeDirectory, patience: Duration = .seconds(15)
  ) {
    self.launcher = launcher
    self.clock = clock
    self.search = search
    self.workingDirectory = workingDirectory
    self.patience = patience
  }

  /// The models in the program's own order; empty when it is not installed, cannot list its models, or
  /// answers with something Loci cannot read.
  public func models(of provider: Provider) async -> [String] {
    guard let cli = AgentCLI.all.first(where: { $0.provider == provider }),
      let executable = search.executable(named: cli.names)
    else { return [] }
    switch provider {
    case .claudeCode:
      return ["fable", "opus", "sonnet", "haiku"]
    case .codex:
      return Self.codexModels(in: await output(of: executable, ["debug", "models"]))
    case .pi:
      return Self.piModels(in: await output(of: executable, ["--list-models"]))
    case .antigravity:
      return Self.antigravityModels(in: await output(of: executable, ["models"]))
    case .bundledPi, .omp, .grok, .cursor, .fx, .hermes, .opencode:
      return []
    }
  }

  private func output(of executable: URL, _ arguments: [String]) async -> String {
    await OneShot(launcher: launcher, clock: clock).output(
      Invocation(executable: executable, arguments: arguments, workingDirectory: workingDirectory), within: patience)
      ?? ""
  }

  /// `provider/model` for each row of Pi's table, after its header.
  static func piModels(in table: String) -> [String] {
    table.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
      let columns = line.split(whereSeparator: \.isWhitespace)
      guard columns.count >= 2 else { return nil }
      return "\(columns[0])/\(columns[1])"
    }
  }

  /// The first column of each `id<TAB>name` row `agy models` prints.
  static func antigravityModels(in rows: String) -> [String] {
    rows.split(whereSeparator: \.isNewline).compactMap { line in
      let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard columns.count >= 2, !columns[0].isEmpty else { return nil }
      return String(columns[0])
    }
  }

  /// The slugs of the models Codex lists in its own picker.
  static func codexModels(in catalog: String) -> [String] {
    guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(catalog.utf8)) else { return [] }
    return (json["models"]?.array ?? []).compactMap { model in
      model["visibility"]?.string == "list" ? model["slug"]?.string : nil
    }
  }
}
