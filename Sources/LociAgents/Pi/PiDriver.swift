import Foundation
import LociModel

/// Drives Pi through `pi --mode rpc`.
public struct PiDriver: AgentDriver {
  public let provider = Mentor.Provider.pi

  private let executable: URL
  private let arguments: [String]
  private let environment: [String: String]?
  private let launcher: any ProgramLauncher
  private let clock: any Clock<Duration>

  /// - Parameters:
  ///   - executable: Where `pi` is installed.
  ///   - arguments: Extra arguments for every session, after the ones the driver chooses.
  ///   - environment: Pi's whole environment; `nil` passes on this process's own.
  public init(
    executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.launcher = launcher
    self.clock = clock
  }

  /// The extension that makes Pi ask before a tool changes anything; Pi has no permission system of its own.
  public static var askBeforeTools: URL? {
    Bundle.module.url(forResource: "ask-before-tools", withExtension: "ts", subdirectory: "Resources")
  }

  public func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    let program = try launcher.launch(
      Invocation(
        executable: executable, arguments: try self.arguments(for: configuration),
        workingDirectory: configuration.workingDirectory, environment: environment))
    let channel = PiChannel(program: program, clock: clock)
    do throws(AgentError) {
      let state = try await channel.request(.getState, within: .seconds(45))
      guard let id = state["sessionId"]?.string else { throw AgentError.rejected("get_state") }
      return PiSession(
        handle: SessionHandle(provider: .pi, value: id), channel: channel,
        window: state["model"]?["contextWindow"]?.int)
    } catch {
      await channel.shutDown(patience: .zero)
      if configuration.resume != nil, case .exited(_, let said) = error, said.contains("No session found") {
        throw .sessionNotFound
      }
      throw error
    }
  }

  private func arguments(for configuration: SessionConfiguration) throws(AgentError) -> [String] {
    var all = ["--mode", "rpc"]
    if let resume = configuration.resume {
      guard resume.provider == .pi else { throw .sessionNotFound }
      all += ["--session", resume.value]
    }
    if let model = configuration.model { all += ["--model", model] }
    if configuration.permission == .ask {
      guard let gate = Self.askBeforeTools else { throw .cannotLaunch("ask-before-tools.ts") }
      all += ["--extension", gate.path]
    }
    return all + arguments
  }
}
