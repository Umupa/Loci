public enum AgentError: Error, Hashable, Sendable {
  /// The program is missing or would not start.
  case cannotLaunch(String)
  /// The program is there but would not start: this Mac did not let it run, or it is broken.
  case wouldNotStart
  /// The session to resume no longer exists.
  case sessionNotFound
  case turnInProgress
  /// The program refused a command.
  case rejected(String)
  /// The model's side failed: quota, network, sign-in. Carries the provider's own words.
  case provider(String)
  /// The program ended on its own. Carries the last of what it wrote to standard error.
  case exited(code: Int32, diagnostics: String)
  /// The program did not answer the named command in time.
  case unresponsive(String)
}
