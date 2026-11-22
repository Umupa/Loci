import Foundation
import LociAgents
import LociMedia
import LociModel
import LociStore

public struct BundledPiEnvironment: Sendable {
  let launcher: any ProgramLauncher
  let clock: any Clock<Duration>
  let variables: [String: String]
  let package: @Sendable (Bool) -> PiPackage

  public init(
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock(),
    variables: [String: String] = ProcessInfo.processInfo.environment,
    package: @escaping @Sendable (Bool) -> PiPackage = { PiPackage.official(arm: $0) }
  ) {
    self.launcher = launcher
    self.clock = clock
    self.variables = variables
    self.package = package
  }

  func driver(
    executable: URL, directory: URL, tool: AgentTool?, credential: ModelServices.PiCredential? = nil
  ) -> PiDriver {
    let systemPaths = "/usr/bin:/bin:/usr/sbin:/sbin"
    let path = tool.map { $0.folder.path(percentEncoded: false) + ":" + systemPaths } ?? systemPaths
    var environment = variables.filter { ["HOME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "TERM"].contains($0.key) }
    environment["PATH"] = path
    environment["PI_CODING_AGENT_DIR"] = directory.path(percentEncoded: false)
    environment["PI_OFFLINE"] = "1"
    environment["PI_TELEMETRY"] = "0"
    if let tool {
      environment[LocalCall.socketVariable] = tool.socket.path(percentEncoded: false)
      environment[LocalCall.commandVariable] = tool.folder.appending(path: "loci").path(percentEncoded: false)
    }
    if let credential, let key = credential.key {
      environment[credential.service.provider.piKeyVariable] = key
    }
    return PiDriver.bundled(
      executable: executable, environment: environment, launcher: launcher, clock: clock, ephemeral: credential == nil)
  }

  func smokeTest(_ executable: URL, in directory: URL, version: String) async throws(FetchError) {
    let driver = driver(executable: executable, directory: directory, tool: nil)
    guard await driver.version(in: directory) == version else {
      throw FetchError(reason: "The Pi executable did not report version \(version).")
    }
    do throws(AgentError) {
      let session = try await driver.open(SessionConfiguration(workingDirectory: directory))
      await session.close()
    } catch {
      throw FetchError(reason: "Pi could not start: \(error.explanation)")
    }
  }
}

extension ModelServiceProvider {
  var piProvider: String {
    switch self {
    case .openAI: "openai"
    case .anthropic: "anthropic"
    case .openRouter: "openrouter"
    case .deepSeek: "deepseek"
    case .compatible: "loci-compatible"
    }
  }

  var piKeyVariable: String {
    switch self {
    case .openAI: "OPENAI_API_KEY"
    case .anthropic: "ANTHROPIC_API_KEY"
    case .openRouter: "OPENROUTER_API_KEY"
    case .deepSeek: "DEEPSEEK_API_KEY"
    case .compatible: "LOCI_MODEL_API_KEY"
    }
  }
}
