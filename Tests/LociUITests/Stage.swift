import Testing

/// Tests that put a window on screen share the main thread, which lays out and draws for all of them. Every
/// test runs at once in one process, so without a limit a test waiting for its window to be ready waits on every
/// other window in the run, and a wait that holds on a laptop runs out on a runner with three cores. A suite
/// marked `.onStage` runs each of its tests with one of a few seats, so a wait measures its own window and a
/// few others, however many tests the run has. A test that keeps the main thread busy throughout, such as one
/// that streams a long reply, takes every seat with `.onStage(alone: true)`.
struct OnStage: TestTrait, SuiteTrait, TestScoping {
  let alone: Bool

  var isRecursive: Bool { true }

  func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
    testCase == nil ? nil : self
  }

  func provideScope(
    for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
  ) async throws {
    let seats = alone ? Stage.seats : 1
    await Stage.shared.enter(seats)
    do {
      try await Stage.$seated.withValue(true) { try await function() }
    } catch {
      await Stage.shared.leave(seats)
      throw error
    }
    await Stage.shared.leave(seats)
  }
}

extension Trait where Self == OnStage {
  /// Runs each test with a seat on the main thread; see `OnStage`.
  static var onStage: OnStage { OnStage(alone: false) }

  /// Runs each test with the main thread to itself; see `OnStage`.
  static func onStage(alone: Bool) -> OnStage { OnStage(alone: alone) }
}

/// The seats tests with windows take, handed out first come, first served, so a test that needs them all is
/// not passed over by ones that need one.
actor Stage {
  static let seats = 3
  static let shared = Stage()

  /// Whether the running test holds a seat.
  @TaskLocal static var seated = false

  private var taken = 0
  private var waiting: [(seats: Int, turn: CheckedContinuation<Void, Never>)] = []

  func enter(_ seats: Int) async {
    if waiting.isEmpty, taken + seats <= Self.seats {
      taken += seats
      return
    }
    await withCheckedContinuation { waiting.append((seats, $0)) }
  }

  func leave(_ seats: Int) {
    taken -= seats
    while let next = waiting.first, taken + next.seats <= Self.seats {
      waiting.removeFirst()
      taken += next.seats
      next.turn.resume()
    }
  }
}
