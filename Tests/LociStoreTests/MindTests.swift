import Foundation
import LociModel
import Testing

@testable import LociStore

struct MindTests {
  private func touch(_ store: Store, _ path: String, secondsAgo: Double) throws {
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -secondsAgo)],
      ofItemAtPath: store.root.appending(path: path).path(percentEncoded: false))
  }

  @Test func theMindHasTheSoulAndListsMemoryFilesNewestFirst() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      let folder = "mentors/\(try store.folderName(ofMentor: mentor.id))"
      try store.writeFile("\(folder)/SOUL.md", "# Soul")
      try store.writeFile("\(folder)/memory/learner.md", "Knows Go.")
      try store.writeFile("\(folder)/memory/topics/syscalls.md", "Asked twice.")
      try touch(store, "\(folder)/memory/learner.md", secondsAgo: 60)

      let mind = try store.mind(of: mentor.id)

      #expect(mind.soul == "# Soul")
      #expect(mind.soulFile.lastPathComponent == "SOUL.md")
      #expect(mind.memory.map(\.name) == ["topics/syscalls.md", "learner.md"])
      #expect(mind.memory.map(\.text) == ["Asked twice.", "Knows Go."])
    }
  }

  @Test func aMentorWithoutSoulOrMemoryHasAnEmptyMind() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)

      let mind = try store.mind(of: mentor.id)

      #expect(mind.soul == nil)
      #expect(mind.memory.isEmpty)
    }
  }

  @Test func filesThatAreNotTextAreLeftOut() throws {
    try withStore { store in
      let mentor = try Fixture.mentor()
      try store.create(mentor)
      let folder = "mentors/\(try store.folderName(ofMentor: mentor.id))"
      try store.write(Data([0xFF, 0xFE, 0x00]), to: store.root.appending(path: "\(folder)/memory/blob.bin"))
      try store.writeFile("\(folder)/memory/.DS_Store", "x")
      try store.writeFile("\(folder)/memory/notes.md", "Kept.")

      #expect(try store.mind(of: mentor.id).memory.map(\.name) == ["notes.md"])
    }
  }
}
