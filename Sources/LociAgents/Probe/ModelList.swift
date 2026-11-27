import Foundation
import LociModel

/// Asks an agent program which models it can run: the names its sessions take, and how it shows them.
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
  public func models(of provider: Provider) async -> [AgentModel] {
    guard let cli = AgentCLI.all.first(where: { $0.provider == provider }),
      let executable = search.executable(named: cli.names)
    else { return [] }
    switch provider {
    case .claudeCode:
      return ["fable", "opus", "sonnet", "haiku"].map { AgentModel(id: $0, name: $0.capitalized) }
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

  /// `provider/model` for each row of Pi's table, after its header, shown as the model.
  static func piModels(in table: String) -> [AgentModel] {
    table.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
      let columns = line.split(whereSeparator: \.isWhitespace)
      guard columns.count >= 2 else { return nil }
      return AgentModel(id: "\(columns[0])/\(columns[1])", name: String(columns[1]))
    }
  }

  /// The `id<TAB>name` rows `agy models` prints. A model listed once for each of several efforts, such as
  /// `gemini-4-hydrogen-high` and `Gemini 4 Hydrogen (High)`, is one model: the effort is chosen on its own.
  static func antigravityModels(in rows: String) -> [AgentModel] {
    let listed = rows.split(whereSeparator: \.isNewline).compactMap { line -> (AgentModel, AgentModel)? in
      let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard columns.count >= 2, !columns[0].isEmpty else { return nil }
      let model = AgentModel(id: String(columns[0]), name: columns[1].trimmingCharacters(in: .whitespaces))
      return (model, withoutEffort(model) ?? model)
    }
    var models: [AgentModel] = []
    for (model, family) in listed {
      let shared = listed.filter { $0.1.id == family.id }.count > 1
      let shown = shared ? family : model
      if !models.contains(where: { $0.id == shown.id }) { models.append(shown) }
    }
    return models
  }

  private static func withoutEffort(_ model: AgentModel) -> AgentModel? {
    for (effort, shown) in [("low", "Low"), ("medium", "Medium"), ("high", "High"), ("xhigh", "XHigh")] {
      guard model.id.hasSuffix("-\(effort)"), model.name.hasSuffix(" (\(shown))") else { continue }
      return AgentModel(
        id: String(model.id.dropLast(effort.count + 1)), name: String(model.name.dropLast(shown.count + 3)))
    }
    return nil
  }

  /// The models Codex lists in its own picker, by slug, shown by their display names.
  static func codexModels(in catalog: String) -> [AgentModel] {
    guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(catalog.utf8)) else { return [] }
    return (json["models"]?.array ?? []).compactMap { model in
      guard model["visibility"]?.string == "list", let slug = model["slug"]?.string else { return nil }
      return AgentModel(id: slug, name: model["display_name"]?.string ?? slug)
    }
  }
}
