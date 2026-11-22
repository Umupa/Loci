import Foundation
import LociModel

/// Drives Pi through `pi --mode rpc`.
public struct PiDriver: AgentDriver {
  public var provider: Provider { variant.provider }

  private let executable: URL
  private let arguments: [String]
  private let environment: [String: String]?
  private let launcher: any ProgramLauncher
  private let clock: any Clock<Duration>
  private let variant: PiVariant

  /// - Parameters:
  ///   - executable: Where `pi` is installed.
  ///   - arguments: Extra arguments for every session, after the ones the driver chooses.
  ///   - environment: Pi's whole environment; `nil` passes on this process's own.
  public static func pi(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) -> PiDriver {
    PiDriver(
      variant: .pi, executable: executable, arguments: arguments, environment: environment, launcher: launcher,
      clock: clock)
  }

  public static func bundled(
    executable: URL, environment: [String: String], launcher: any ProgramLauncher = SystemLauncher(),
    clock: any Clock<Duration> = ContinuousClock(), ephemeral: Bool = false
  ) -> PiDriver {
    PiDriver(
      variant: .bundled, executable: executable, arguments: ephemeral ? ["--no-session"] : [],
      environment: environment, launcher: launcher, clock: clock)
  }

  public func models(in workingDirectory: URL, matching provider: String) async -> [String] {
    let output = await OneShot(launcher: launcher, clock: clock).output(
      Invocation(
        executable: executable, arguments: ["--list-models", provider] + variant.scopeArguments,
        workingDirectory: workingDirectory, environment: environment),
      within: .seconds(15))
    return ModelList.piModels(in: output ?? "").filter { $0.hasPrefix(provider + "/") }
  }

  public func version(in workingDirectory: URL) async -> String? {
    await OneShot(launcher: launcher, clock: clock).output(
      Invocation(
        executable: executable, arguments: ["--version"],
        workingDirectory: workingDirectory, environment: environment),
      within: .seconds(45))?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  init(
    variant: PiVariant, executable: URL, arguments: [String], environment: [String: String]?,
    launcher: any ProgramLauncher, clock: any Clock<Duration>
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.launcher = launcher
    self.clock = clock
    self.variant = variant
  }

  public func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    let program = try launcher.launch(
      Invocation(
        executable: executable, arguments: try self.arguments(for: configuration),
        workingDirectory: configuration.workingDirectory, environment: configuration.environment(over: environment)))
    let channel = PiChannel(program: program, clock: clock)
    do throws(AgentError) {
      let state = try await channel.request(.getState, within: .seconds(45))
      guard let id = state["sessionId"]?.string else { throw AgentError.rejected("get_state") }
      return PiSession(
        handle: SessionHandle(provider: provider, value: id), channel: channel,
        window: state["model"]?["contextWindow"]?.int, clock: clock)
    } catch {
      await channel.connection.shutDown(patience: .zero)
      if configuration.resume != nil, case .exited(_, let said) = error, variant.sessionIsMissing(said) {
        throw .sessionNotFound
      }
      throw error
    }
  }

  private func arguments(for configuration: SessionConfiguration) throws(AgentError) -> [String] {
    var all = variant.launchArguments
    if let resume = configuration.resume {
      guard resume.provider == provider else { throw .sessionNotFound }
      all += [variant.resumeFlag, resume.value]
    }
    if let model = configuration.model { all += ["--model", model] }
    if let effort = configuration.effort, provider.efforts.contains(effort) { all += ["--thinking", effort.rawValue] }
    return all + arguments
  }
}
