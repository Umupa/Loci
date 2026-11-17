import Foundation

extension AcpDriver {
  /// Antigravity's standalone `agy_acp_server.par`, launched beside its bundled resources.
  public static func antigravity(
    executable: URL, extra: [String] = [], environment: [String: String]? = nil,
    launcher: any ProgramLauncher = SystemLauncher(), clock: any Clock<Duration> = ContinuousClock()
  ) -> AcpDriver {
    var driver = AcpDriver(
      provider: .antigravity, executable: executable, arguments: { _ in extra },
      environment: environment, launcher: launcher, clock: clock)
    driver.processDirectory = executable.deletingLastPathComponent()
    driver.supportsConfigOptions = true
    driver.configureSession = configureAntigravity
    driver.replyFailure = { text in
      let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return message.hasPrefix("No capacity available for model ") && message.hasSuffix(" on the server")
        ? message : nil
    }
    return driver
  }

  private static func configureAntigravity(
    _ channel: AcpChannel, _ setup: JSONValue, _ session: String, _ configuration: SessionConfiguration
  ) async throws(AgentError) {
    _ = try await channel.request(
      "session/set_mode",
      .object([
        "sessionId": .string(session), "modeId": .string(configuration.permission == .full ? "yolo" : "default"),
      ]), within: .seconds(15))
    if let model = configuration.model {
      let options = setup["configOptions"]?.array ?? []
      guard
        let selector = options.first(where: { $0["id"]?.string == "model" && $0["type"]?.string != "boolean" })
          ?? options.first(where: {
            $0["category"]?.string == "model" && $0["id"]?.string != "provider" && $0["type"]?.string != "boolean"
          }),
        let id = selector["id"]?.string
      else { throw .rejected("Antigravity did not advertise a model selector") }
      _ = try await channel.request(
        "session/set_config_option",
        .object([
          "sessionId": .string(session), "configId": .string(id), "value": .string(model),
        ]), within: .seconds(15))
    }
  }
}
