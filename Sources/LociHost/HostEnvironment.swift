import Foundation
import LociModel
import LociStore

/// What a host takes from the outside world, so tests can choose it.
public struct HostEnvironment: Sendable {
  public let newID: @Sendable () -> EntityID
  public let now: @Sendable () -> Timestamp
  /// The agent new mentors run on until settings can change it.
  public let defaultProvider: Mentor.Provider
  /// How deleted mentors and items leave the disk.
  public let discard: Discard

  public init(
    newID: @escaping @Sendable () -> EntityID, now: @escaping @Sendable () -> Timestamp,
    defaultProvider: Mentor.Provider, discard: Discard
  ) {
    self.newID = newID
    self.now = now
    self.defaultProvider = defaultProvider
    self.discard = discard
  }

  /// The real clock, fresh identifiers, and the Trash.
  public static func system(defaultProvider: Mentor.Provider) -> HostEnvironment {
    HostEnvironment(
      newID: { EntityID() }, now: { Timestamp(.now) }, defaultProvider: defaultProvider, discard: .toTrash)
  }
}
