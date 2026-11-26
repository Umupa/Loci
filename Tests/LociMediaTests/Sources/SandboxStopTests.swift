import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociMedia

/// DS-S4: a script that will not stop never keeps its fetch's place: the page is asked to end it until a
/// deadline, then closed by the app whatever it is doing, and a fetch that is cancelled stops it the same way.
@MainActor
struct SandboxStopTests {
  static let now = Timestamp(millisecondsSince1970: 1_764_000_000_000)

  /// A page that loads, and then answers nothing it is asked until it is closed, or ends its worker only
  /// from the `endsOn`th time it is asked.
  final class StuckPage: SandboxPage {
    private(set) var asked = 0
    private(set) var closed = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    let endsOn: Int?

    init(endsOn: Int? = nil) {
      self.endsOn = endsOn
    }

    func load() async -> Bool { true }

    func evaluate(_ body: String, input: String) async -> Result<String, SourceProblems> {
      await hang()
      return .failure(SourceProblems("script", "its page was closed"))
    }

    func endWorker() async -> Bool {
      asked += 1
      if let endsOn, asked >= endsOn { return true }
      await hang()
      return false
    }

    func close() {
      closed = true
      let woken = waiting
      waiting = []
      for continuation in woken { continuation.resume() }
    }

    private func hang() async {
      guard !closed else { return }
      await withCheckedContinuation { waiting.append($0) }
    }
  }

  static func run(
    _ page: StuckPage, timeout: Duration = .milliseconds(100), stopping: Duration = .milliseconds(400),
    ended: Flag
  ) async -> SourceProblems? {
    do throws(SourceProblems) {
      _ = try await ParseSandbox.run(
        "function parse() { while (true) {} }", .parse(responses: []), now: now, timeout: timeout, stopping: stopping,
        page: { page }, ended: ended.set)
      return nil
    } catch {
      return error
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func aPageThatNeverEndsItsWorkerIsClosedByTheStoppingDeadline() async {
    let page = StuckPage()
    let ended = Flag()
    let started = ContinuousClock.now

    let problems = await Self.run(page, ended: ended)

    #expect(
      problems == SourceProblems("script", "ran longer than 0.1 seconds; its page did not stop it and was closed"))
    #expect(ContinuousClock.now - started < .milliseconds(100) + ParseSandbox.grace + .milliseconds(400) + .seconds(1))
    #expect(page.asked >= 1 && page.closed)
    #expect(ended.isSet)
  }

  @Test(.timeLimit(.minutes(1)))
  func aPageIsAskedAgainUntilItEndsItsWorker() async {
    let page = StuckPage(endsOn: 2)
    let ended = Flag()

    let problems = await Self.run(page, stopping: .seconds(5), ended: ended)

    #expect(problems == SourceProblems("script", "ran longer than 0.1 seconds and was stopped"))
    #expect(page.asked == 2 && page.closed)
    #expect(ended.isSet)
  }

  @Test(.timeLimit(.minutes(1)))
  func aCancelledRunStopsItsScriptAndGivesItsPlaceBackAtOnce() async {
    let page = StuckPage()
    let ended = Flag()
    let started = ContinuousClock.now

    let running = Task { await Self.run(page, timeout: .seconds(30), ended: ended) }
    try? await Task.sleep(for: .milliseconds(100))
    running.cancel()
    let problems = await running.value

    #expect(problems == ParseSandbox.cancelled)
    #expect(ContinuousClock.now - started < .seconds(2))
    #expect(page.asked >= 1 && page.closed)
    #expect(ended.isSet)
  }

  @Test(.timeLimit(.minutes(1)))
  func aCancelledScriptInARealPageIsStopped() async {
    let ended = Flag()
    let started = ContinuousClock.now

    let running = Task { () async -> SourceProblems? in
      do throws(SourceProblems) {
        _ = try await ParseSandbox.run(
          "function parse() { while (true) {} }", .parse(responses: []), now: Self.now, timeout: .seconds(30),
          ended: ended.set)
        return nil
      } catch {
        return error
      }
    }
    try? await Task.sleep(for: .milliseconds(500))
    running.cancel()
    let problems = await running.value

    #expect(problems == ParseSandbox.cancelled)
    #expect(ContinuousClock.now - started < .seconds(5))
    #expect(ended.isSet)
  }
}

/// Whether something was told.
final class Flag: Sendable {
  private let told = Mutex(false)

  var isSet: Bool { told.withLock { $0 } }

  @Sendable func set() {
    told.withLock { $0 = true }
  }
}
