/// Lets at most `limit` callers through at once; the rest wait their turn in order.
actor Gate {
  private let limit: Int
  private var inside = 0
  private var waiting: [CheckedContinuation<Void, Never>] = []

  init(limit: Int) {
    self.limit = limit
  }

  var isBusy: Bool { inside > 0 }

  func enter() async {
    guard inside >= limit else {
      inside += 1
      return
    }
    await withCheckedContinuation { waiting.append($0) }
  }

  /// Hands the place straight to the next in line, if any.
  func leave() {
    if waiting.isEmpty {
      inside -= 1
    } else {
      waiting.removeFirst().resume()
    }
  }

  nonisolated func through<Value: Sendable, Failure: Error>(_ body: () async throws(Failure) -> Value)
    async throws(Failure) -> Value
  {
    await enter()
    do {
      let value = try await body()
      await leave()
      return value
    } catch {
      await leave()
      throw error
    }
  }
}
