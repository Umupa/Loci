import Foundation

/// Starts real programs and turns their pipes into streams.
public struct SystemLauncher: ProgramLauncher {
  public init() {}

  public func launch(_ invocation: Invocation) throws(AgentError) -> RunningProgram {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let diagnostics = Pipe()
    process.executableURL = invocation.executable
    process.arguments = invocation.arguments
    process.currentDirectoryURL = invocation.workingDirectory
    if let environment = invocation.environment { process.environment = environment }
    process.standardInput = input
    process.standardOutput = output
    process.standardError = diagnostics

    let (exits, exited) = AsyncStream.makeStream(of: Int32.self)
    process.terminationHandler = { ended in
      exited.yield(ended.terminationStatus)
      exited.finish()
    }
    let status = Task {
      for await code in exits { return code }
      return Int32(-1)
    }

    let writer = input.fileHandleForWriting
    _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
    do {
      try process.run()
    } catch {
      exited.finish()
      throw .cannotLaunch(error.localizedDescription)
    }
    let identifier = process.processIdentifier

    return RunningProgram(
      output: Self.chunks(from: output.fileHandleForReading),
      diagnostics: Self.chunks(from: diagnostics.fileHandleForReading),
      write: { data in try writer.write(contentsOf: data) },
      closeInput: { try? writer.close() },
      terminate: { kill(identifier, SIGTERM) },
      exit: { await status.value })
  }

  private static func chunks(from handle: FileHandle) -> AsyncStream<Data> {
    let (chunks, continuation) = AsyncStream.makeStream(of: Data.self)
    handle.readabilityHandler = { reader in
      let data = reader.availableData
      if data.isEmpty {
        reader.readabilityHandler = nil
        continuation.finish()
      } else {
        continuation.yield(data)
      }
    }
    continuation.onTermination = { _ in handle.readabilityHandler = nil }
    return chunks
  }
}
