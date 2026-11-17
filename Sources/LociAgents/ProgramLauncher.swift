import Foundation

/// Starts other programs. Drivers get one from outside, so tests can replay a recording instead.
public protocol ProgramLauncher: Sendable {
  func launch(_ invocation: Invocation) throws(AgentError) -> RunningProgram
}

public struct Invocation: Hashable, Sendable {
  public var executable: URL
  public var arguments: [String]
  public var workingDirectory: URL
  /// The program's whole environment; `nil` passes on this process's own.
  public var environment: [String: String]?

  public init(executable: URL, arguments: [String], workingDirectory: URL, environment: [String: String]? = nil) {
    self.executable = executable
    self.arguments = arguments
    self.workingDirectory = workingDirectory
    self.environment = environment
  }
}

public struct RunningProgram: Sendable {
  /// Standard output in the chunks it arrived in. Finishes when the program closes it.
  public let output: AsyncStream<Data>
  /// Standard error, likewise.
  public let diagnostics: AsyncStream<Data>
  /// Writes to standard input. Throws when the program is no longer reading.
  public let write: @Sendable (Data) throws -> Void
  public let closeInput: @Sendable () -> Void
  /// Asks the program to stop.
  public let terminate: @Sendable () -> Void
  /// The exit status, once the program has ended.
  public let exit: @Sendable () async -> Int32

  public init(
    output: AsyncStream<Data>, diagnostics: AsyncStream<Data>, write: @escaping @Sendable (Data) throws -> Void,
    closeInput: @escaping @Sendable () -> Void, terminate: @escaping @Sendable () -> Void,
    exit: @escaping @Sendable () async -> Int32
  ) {
    self.output = output
    self.diagnostics = diagnostics
    self.write = write
    self.closeInput = closeInput
    self.terminate = terminate
    self.exit = exit
  }
}
