import Foundation
import LociConnect
import LociModel
import Synchronization

/// A calendar and reminders that keep what was written to them in memory. It has the calendars and lists in
/// `targets`, the first being the default; two may share a name. Until it is asked, it lets no one look: like
/// macOS, it shows the calendars only once access is given. A write can be held until released, or followed by
/// `afterMake`; looking and removing can be made to fail, and a sync can give every item a new identifier.
final class FakeWrites: PersonalWrites {
  private struct State {
    var access = Access.unasked
    var targets = [
      ApprovalTarget(id: "cal-1", name: "个人", source: "iCloud"),
      ApprovalTarget(id: "cal-2", name: "家庭", source: "iCloud"),
    ]
    var made: [String: (approval: Approval, marker: String, target: String)] = [:]
    var serial = 0
    var held: [CheckedContinuation<Void, Never>]?
    var afterMake: (@Sendable () -> Void)?
    var blind = false
    var stuck = false
    var looked = 0
    var asking: (@Sendable () async -> Void)?
  }

  enum Access { case unasked, granted, refused }

  private let state = Mutex(State())

  var made: [Approval] { state.withLock { $0.made.values.map(\.approval) } }
  /// The identifier of the calendar or list each was written to.
  var madeIn: [String] { state.withLock { $0.made.values.map(\.target) } }
  var identifiers: [String] { state.withLock { $0.made.keys.sorted() } }
  /// How many times calendars were looked up by name.
  var looked: Int { state.withLock { $0.looked } }

  func refuse() {
    state.withLock { $0.access = .refused }
  }

  func grant() {
    state.withLock { $0.access = .granted }
  }

  func set(targets: [ApprovalTarget]) {
    state.withLock { $0.targets = targets }
  }

  /// Looking for what was written cannot be done, as without access.
  func blindfold() {
    state.withLock { $0.blind = true }
  }

  /// Removing fails.
  func jam() {
    state.withLock { $0.stuck = true }
  }

  /// Something written with `marker` before the app stopped.
  func keep(_ approval: Approval, in target: String, marker: String) -> String {
    state.withLock { state in
      state.serial += 1
      let identifier = "item-\(state.serial)"
      state.made[identifier] = (approval, marker, target)
      return identifier
    }
  }

  /// Writes wait until `release`.
  func hold() {
    state.withLock { $0.held = [] }
  }

  func release() {
    let waiting = state.withLock { state in
      defer { state.held = nil }
      return state.held ?? []
    }
    for one in waiting { one.resume() }
  }

  func afterMake(_ body: @escaping @Sendable () -> Void) {
    state.withLock { $0.afterMake = body }
  }

  /// Runs while macOS would be asking the person for access, the first time.
  func whileAsking(_ body: @escaping @Sendable () async -> Void) {
    state.withLock { $0.asking = body }
  }

  func allow(_ kind: PersonalKind) async -> Bool {
    let asking = state.withLock { state in state.access == .unasked ? state.asking : nil }
    await asking?()
    return state.withLock { state in
      if state.access == .unasked { state.access = .granted }
      return state.access == .granted
    }
  }

  func targets(named name: String?, of kind: PersonalKind) async -> [ApprovalTarget] {
    state.withLock { state in
      state.looked += 1
      guard state.access == .granted else { return [] }
      guard let name else { return Array(state.targets.prefix(1)) }
      return state.targets.filter { $0.name == name }
    }
  }

  func make(_ approval: Approval, in target: ApprovalTarget, marker: String) async throws(WriteFailure) -> String {
    await withCheckedContinuation { done in
      let waits = state.withLock { state in
        guard state.held != nil else { return false }
        state.held?.append(done)
        return true
      }
      if !waits { done.resume() }
    }
    let result: Result<String, WriteFailure> = state.withLock { state in
      guard state.access == .granted else { return .failure(.failed("no access")) }
      guard state.targets.contains(where: { $0.id == target.id }) else { return .failure(.targetGone(target.name)) }
      state.serial += 1
      let identifier = "item-\(state.serial)"
      state.made[identifier] = (approval, marker, target.id)
      return .success(identifier)
    }
    let identifier = try result.get()
    state.withLock { $0.afterMake }?()
    return identifier
  }

  func find(_ marker: String, for approval: Approval, in target: ApprovalTarget) async -> Lookup {
    state.withLock { state in
      guard !state.blind else { return .unknown }
      return state.made.first { $0.value.marker == marker }.map { .found($0.key) } ?? .absent
    }
  }

  /// Like a sync with the server: every item keeps its marker but gets a new identifier.
  func resync() {
    state.withLock { state in
      state.made = Dictionary(uniqueKeysWithValues: state.made.map { ("synced-\($0.key)", $0.value) })
    }
  }

  func remove(_ made: Approved, for approval: Approval) async throws(WriteFailure) {
    let stuck = state.withLock { state in
      guard !state.stuck else { return true }
      let key =
        state.made[made.identifier] != nil
        ? made.identifier : state.made.first { $0.value.marker == made.marker }?.key
      if let key { state.made.removeValue(forKey: key) }
      return false
    }
    if stuck { throw .failed("could not remove") }
  }
}
