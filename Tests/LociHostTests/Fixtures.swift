import Foundation
import LociModel
import LociStore
import Synchronization
import Testing

@testable import LociHost

/// Identifiers in a fixed sequence and a clock that never moves.
final class TestWorld: Sendable {
  private let created = Mutex<UInt64>(0)
  static let instant = Timestamp(millisecondsSince1970: 1_763_337_600_123)

  var environment: HostEnvironment {
    HostEnvironment(
      newID: { [self] in self.nextID() }, now: { Self.instant }, defaultProvider: .pi, discard: .permanently)
  }

  func nextID() -> EntityID {
    let seed = created.withLock { count in
      count += 1
      return count
    }
    var entropy = SeededGenerator(seed: seed)
    return EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + Double(seed)), entropy: &entropy)
  }
}

/// A temporary Loci folder and database location, deleted afterwards.
struct Place {
  let root: URL
  var database: URL { root.appending(path: "loci.sqlite") }
  var store: Store { Store(root: root, discard: .permanently) }

  init() {
    root = FileManager.default.temporaryDirectory.appending(path: "loci-host-\(UUID().uuidString)")
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  /// Rewrites a file the way an agent or the Finder would, without going through the host.
  func edit(_ url: URL, _ change: (String) -> String) throws {
    try Data(change(try String(contentsOf: url, encoding: .utf8)).utf8).write(to: url)
  }
}

/// Runs `body` against a host started in a new temporary place, then closes it and deletes the place.
func withHost(_ body: (LocalHost, Place, TestWorld) async throws -> Void) async throws {
  let place = Place()
  defer { place.remove() }
  let world = TestWorld()
  let host = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
  do {
    try await body(host, place, world)
  } catch {
    await host.close()
    throw error
  }
  await host.close()
}

/// The first value the feed delivers that satisfies `match`, or `nil` after `timeout`.
func first<Value: Sendable>(
  _ feed: AsyncStream<Feed<Value>>, within timeout: Duration = .seconds(5),
  where match: @escaping @Sendable (Feed<Value>) -> Bool
) async -> Feed<Value>? {
  await withTaskGroup(of: Feed<Value>?.self) { group in
    group.addTask {
      for await delivered in feed where match(delivered) { return delivered }
      return nil
    }
    group.addTask {
      try? await Task.sleep(for: timeout)
      return nil
    }
    let found = await group.next() ?? nil
    group.cancelAll()
    return found
  }
}

func value<Value: Sendable>(
  _ feed: AsyncStream<Feed<Value>>, within timeout: Duration = .seconds(5),
  where match: @escaping @Sendable (Value) -> Bool
) async -> Value? {
  let found = await first(feed, within: timeout) { delivered in
    if case .value(let value) = delivered { return match(value) }
    return false
  }
  guard case .value(let value) = found else { return nil }
  return value
}

struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
  }
}
