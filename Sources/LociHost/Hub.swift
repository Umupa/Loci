import Foundation
import LociModel

/// The host's only mutable state: who is subscribed, the current health, the background tasks, and the
/// files handed over for commands still to come.
actor Hub {
  private var watchers: [Int: any Refreshing] = [:]
  private var uploads: [EntityID: URL] = [:]
  private var nextWatcher = 0
  private var health: Health
  private var tasks: [Task<Void, Never>] = []

  init(health: Health) {
    self.health = health
  }

  func current() -> Health { health }

  func add(_ watcher: any Refreshing) -> Int {
    nextWatcher += 1
    watchers[nextWatcher] = watcher
    return nextWatcher
  }

  func remove(_ watcher: Int) {
    watchers[watcher] = nil
  }

  func keep(_ file: URL, as upload: EntityID) {
    uploads[upload] = file
  }

  /// The file an upload names, once; a second command with the same upload finds nothing.
  func takeUpload(_ upload: EntityID) -> URL? {
    uploads.removeValue(forKey: upload)
  }

  func hold(_ task: Task<Void, Never>) {
    tasks.append(task)
  }

  /// Cancels the background work and returns once it has ended, so nothing writes to the database after.
  func stop() async {
    let stopping = tasks
    tasks = []
    for task in stopping { task.cancel() }
    for task in stopping { await task.value }
  }

  /// A full rebuild knows every problem there is.
  func rebuilt(problems: [FileProblem]) {
    health = Health(database: .ready, readingStateLost: health.readingStateLost, fileProblems: problems)
  }

  /// Following changes re-reads only some files, so only their owners' problems are replaced.
  func followed(_ changes: Set<ContentChange>, problems: [FileProblem]) {
    if changes.contains(.everything) {
      rebuilt(problems: problems)
      return
    }
    let reread = Set(changes.compactMap(\.problemSubject))
    let kept = health.fileProblems.filter {
      guard let subject = $0.subject else { return true }
      if case .notes(.lesson(let course, _)) = subject, reread.contains(.course(course)) { return false }
      return !reread.contains(subject)
    }
    health = Health(database: health.database, readingStateLost: health.readingStateLost, fileProblems: kept + problems)
  }

  func failed(_ reason: String) {
    health = Health(
      database: .failed(reason), readingStateLost: health.readingStateLost, fileProblems: health.fileProblems)
  }

  /// Recomputes every subscription the changes could affect, all at once.
  func refresh(_ changes: Set<ContentChange>) async {
    let affected = watchers.values.filter { $0.isAffected(by: changes) }
    await withTaskGroup(of: Void.self) { group in
      for watcher in affected { group.addTask { await watcher.refresh() } }
    }
  }
}

extension ContentChange {
  var problemSubject: FileProblem.Subject? {
    switch self {
    case .item(let id): .item(id)
    case .course(let id): .course(id)
    case .courseActivity: nil
    case .notes(let content): .notes(content)
    case .everything, .reading, .job, .media, .conversation, .turnEnded, .review, .loci, .runtime, .timers, .connectors,
      .projects, .source:
      nil
    }
  }
}

protocol Refreshing: Actor {
  nonisolated func isAffected(by changes: Set<ContentChange>) -> Bool
  func refresh() async
}

/// One subscriber: computes the value again when asked and sends it on only if it changed.
actor Watcher<S: Subscription>: Refreshing {
  private let subscription: S
  private let handler: any CommandHandler
  private let continuation: AsyncStream<Feed<S.Value>>.Continuation
  private var last: Feed<S.Value>?
  private var generation = 0

  init(_ subscription: S, handler: any CommandHandler, continuation: AsyncStream<Feed<S.Value>>.Continuation) {
    self.subscription = subscription
    self.handler = handler
    self.continuation = continuation
  }

  nonisolated func isAffected(by changes: Set<ContentChange>) -> Bool {
    subscription.isAffected(by: changes)
  }

  /// A refresh that finishes after a later one started is dropped, so an old value never follows a new one.
  func refresh() async {
    generation += 1
    let started = generation
    let feed: Feed<S.Value>
    do {
      feed = .value(try await subscription.value(from: handler))
    } catch {
      feed = .unavailable(error)
    }
    guard started == generation, feed != last else { return }
    last = feed
    continuation.yield(feed)
  }
}
