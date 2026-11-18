import Foundation

/// Starts real programs.
public struct SystemRunner: ProgramRunner {
  public init() {}

  public func run(_ call: ProgramCall, line: @escaping @Sendable (String) -> Void) async throws(ProgramError)
    -> ProgramResult
  {
    let process = Process()
    let output = Pipe()
    let diagnostics = Pipe()
    process.executableURL = call.executable
    process.arguments = call.arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = diagnostics
    let (exits, exited) = AsyncStream.makeStream(of: Int32.self)
    process.terminationHandler = { ended in
      exited.yield(ended.terminationStatus)
      exited.finish()
    }
    let lines = Self.chunks(from: output.fileHandleForReading)
    let errors = Self.chunks(from: diagnostics.fileHandleForReading)
    do {
      try process.run()
    } catch {
      throw ProgramError(reason: error.localizedDescription)
    }
    let identifier = process.processIdentifier
    return await withTaskCancellationHandler {
      async let said = Self.collect(lines, line: line)
      async let complained = Self.collect(errors, line: { _ in })
      var status: Int32 = -1
      for await code in exits { status = code }
      return ProgramResult(status: status, output: await said, diagnostics: await complained)
    } onCancel: {
      kill(identifier, SIGTERM)
    }
  }

  private static func collect(_ chunks: AsyncStream<Data>, line: @Sendable (String) -> Void) async -> String {
    var all = Data()
    var pending = Data()
    for await chunk in chunks {
      all.append(chunk)
      pending.append(chunk)
      while let end = pending.firstIndex(of: UInt8(ascii: "\n")) {
        line(String(decoding: pending[pending.startIndex..<end], as: UTF8.self))
        pending = Data(pending[pending.index(after: end)...])
      }
    }
    if !pending.isEmpty { line(String(decoding: pending, as: UTF8.self)) }
    return String(decoding: all, as: UTF8.self)
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
