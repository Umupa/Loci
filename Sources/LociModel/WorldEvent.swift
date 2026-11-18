/// Something that happened in the library, shown in the main conversation where it happened.
public struct WorldEvent: Hashable, Codable, Sendable, Identifiable {
  public let id: EntityID
  public let at: Timestamp
  public let kind: Kind

  public init(id: EntityID, at: Timestamp, kind: Kind) {
    self.id = id
    self.at = at
    self.kind = kind
  }

  public enum Kind: Hashable, Codable, Sendable {
    /// The person read the item to the end.
    case finishedReading(Item)
    /// The item went into the library. `job` is its work while that runs or after it last stopped
    /// (waiting, failed or stopped); `nil` once it is done, or for an item that needs no work.
    case saved(Item, job: Job?)
  }
}
