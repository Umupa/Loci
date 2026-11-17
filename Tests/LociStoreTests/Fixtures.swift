import Foundation
import LociModel

@testable import LociStore

enum Fixture {
  static func id(_ seed: UInt64) -> EntityID {
    var entropy = SeededGenerator(seed: seed)
    return EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + Double(seed)), entropy: &entropy)
  }

  static func slug(_ text: String) -> Lesson.Slug {
    Lesson.Slug(text)!
  }

  static func mentor(_ seed: UInt64 = 1, name: String = "调度") throws -> Mentor {
    try Mentor(
      id: id(seed), name: name, avatar: "owl", color: MentorColor(red: 0xB5, green: 0x52, blue: 0x3B),
      provider: .claudeCode)
  }

  static func item(_ seed: UInt64 = 2, title: String = "Large-scale cluster management at Google with Borg") throws
    -> Item
  {
    try Item(id: id(seed), kind: .article, title: title, authors: ["Abhishek Verma"], language: "en")
  }

  static let instant = Timestamp(millisecondsSince1970: 1_763_337_600_123)
}

/// A store in a new temporary folder. Deletions in tests are permanent: nothing goes to the user's Trash.
func temporaryStore() -> Store {
  Store(
    root: FileManager.default.temporaryDirectory.appending(path: "loci-store-\(UUID().uuidString)"),
    discard: .permanently)
}

/// Runs `body` against a temporary store and deletes its folder afterwards.
func withStore(_ body: (Store) throws -> Void) throws {
  let store = temporaryStore()
  defer { try? FileManager.default.removeItem(at: store.root) }
  try body(store)
}

extension Store {
  func writeFile(_ relativePath: String, _ text: String) throws {
    try write(Data(text.utf8), to: root.appending(path: relativePath))
  }

  func readFile(_ relativePath: String) throws -> String {
    try readText(root.appending(path: relativePath))
  }

  func folderName(ofMentor id: EntityID) throws -> String {
    try mentorFolder(id).lastPathComponent
  }
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
