import Foundation

/// Runs a program that says one thing and stops, and gives up on it after a while.
struct OneShot: Sendable {
  let launcher: any ProgramLauncher
  let clock: any Clock<Duration>

  /// What the program wrote to standard output, or `nil` when it could not start or did not stop in time.
  func output(_ invocation: Invocation, within limit: Duration) async -> String? {
    guard let program = try? launcher.launch(invocation) else { return nil }
    program.closeInput()
    let reading = Task {
      var data = Data()
      for await chunk in program.output { data.append(chunk) }
      _ = await program.exit()
      return String(decoding: data, as: UTF8.self)
    }
    guard let said = await First.of({ await reading.value }, within: limit, clock: clock) else {
      program.terminate()
      return nil
    }
    return said
  }
}

/// The first of two answers, whoever gives it; the other one is dropped.
private actor First<Value: Sendable> {
  private var taken = false

  func take(_ value: Value?, resuming continuation: CheckedContinuation<Value?, Never>) {
    guard !taken else { return }
    taken = true
    continuation.resume(returning: value)
  }

  static func of(
    _ work: @escaping @Sendable () async -> Value, within limit: Duration, clock: any Clock<Duration>
  ) async -> Value? {
    let first = First()
    return await withCheckedContinuation { continuation in
      Task { await first.take(await work(), resuming: continuation) }
      Task {
        try? await clock.sleep(for: limit)
        await first.take(nil, resuming: continuation)
      }
    }
  }
}
