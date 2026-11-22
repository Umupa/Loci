import Foundation

/// Runs other programs to the end. Fetchers get one from outside, so tests can answer in a program's place.
public protocol ProgramRunner: Sendable {
  /// Runs `call` until the program ends. `line` hears each line of standard output as it arrives. Cancelling
  /// the calling task stops the program.
  func run(_ call: ProgramCall, line: @escaping @Sendable (String) -> Void) async throws(ProgramError) -> ProgramResult
}

extension ProgramRunner {
  public func run(_ call: ProgramCall) async throws(ProgramError) -> ProgramResult {
    try await run(call, line: { _ in })
  }
}

public struct ProgramCall: Hashable, Sendable {
  public var executable: URL
  public var arguments: [String]
  public var environment: [String: String]?

  public init(executable: URL, arguments: [String], environment: [String: String]? = nil) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
  }
}

public struct ProgramResult: Hashable, Sendable {
  public let status: Int32
  public let output: String
  public let diagnostics: String

  public init(status: Int32, output: String, diagnostics: String = "") {
    self.status = status
    self.output = output
    self.diagnostics = diagnostics
  }

  public var succeeded: Bool { status == 0 }
}

/// The program could not be started at all.
public struct ProgramError: Error, Hashable, Sendable {
  public let reason: String

  public init(reason: String) {
    self.reason = reason
  }
}
