import Foundation
import LociConnect
import LociModel
import Synchronization

/// A calendar and reminders that keep what was written to them in memory.
final class FakeWrites: PersonalWrites {
  private let state = Mutex<(allowed: Bool, made: [String: Approval], serial: Int)>((true, [:], 0))

  var made: [Approval] { state.withLock { Array($0.made.values) } }

  func refuse() {
    state.withLock { $0.allowed = false }
  }

  func allow(_ kind: PersonalKind) async -> Bool { state.withLock { $0.allowed } }

  func make(_ approval: Approval) async throws(ConnectError) -> String {
    state.withLock { state in
      state.serial += 1
      let identifier = "item-\(state.serial)"
      state.made[identifier] = approval
      return identifier
    }
  }

  func remove(_ identifier: String, of kind: PersonalKind) async throws(ConnectError) {
    _ = state.withLock { $0.made.removeValue(forKey: identifier) }
  }
}
