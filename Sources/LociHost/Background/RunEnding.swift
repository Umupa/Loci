import Foundation
import LociModel
import LociStore

/// How the worker ends a run: whether it did what it was for, what it says of it, and what it puts back.
extension Worker {
  /// A finished follow-up says its last sentence as the companion in the conversation it was set in, kept as a
  /// message with the follow-up's event's id in the same write that closes the run and the event: so it is said
  /// once, even when the app stops between, and never when it cannot be kept, in which case the run is tried
  /// again. Whether it was said, with the result to keep otherwise.
  func sayWhatItFound(_ run: Run, _ result: RunResult, of current: Current) async -> (RunResult, said: Bool) {
    guard case .finished(let reply, let sources) = result, current.repair == nil, current.events.count == 1,
      let event = current.events.first, case .followUp(let id, _) = event.source
    else { return (result, false) }
    let database = context.database
    let conversation = ((try? database.followUp(id)) ?? nil)?.conversation ?? run.kind.home.conversation
    let summary = RunResult.summary(of: reply)
    let closed = run.with(.finished(summary: summary, sources: sources))
    let done = [event.with(.done(run.id))]
    do throws(HostError) {
      try await say(summary, conversation, event.id) { line in try database.close(closed, events: done, saying: line) }
      return (result, true)
    } catch {
      return (.failed("what it found could not be said: \(error)", again: true), false)
    }
  }

  /// A repair is done only when it saved a script that reads the samples its source failed on, while it ran,
  /// whatever its reply says and however the source does now.
  func judged(_ result: RunResult, of current: Current, mended: Bool) -> RunResult {
    guard case .finished = result, current.repair != nil, !mended else { return result }
    return .failed(Self.notMended, again: false)
  }

  static let notMended = "the repair saved no script that reads the samples its source failed on"

  /// After a daily review: on the first split, keeps any entry the review lost; keeps what the review left to
  /// compare against later; and makes the index and wiki read-only again.
  func tidyMemory(of home: Home, after result: RunResult, brief: ReviewBrief?) {
    let store = context.store
    if case .finished = result {
      if let entries = brief?.migrating { _ = try? ReviewBrief.keepLost(entries, store: store) }
      try? store.home(home).keepMemory()
    }
    try? store.home(home).setMemoryWritable(false)
  }

  func changes(of kind: Run.Kind) -> Set<ContentChange> {
    let changes: Set<ContentChange> =
      switch kind {
      case .review: [.timers, .review]
      case .timers: [.timers, .loci(.panels)]
      }
    return kind.home == .chat ? changes : changes.union([.projects, .turnEnded(kind.home.conversation)])
  }
}
