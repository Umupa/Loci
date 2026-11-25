import Foundation
import LociModel
import Testing

@testable import LociStore

/// US-S1: the sessions Loci keeps a handle for, and the files the CLIs keep of them.
struct SessionFilesTests {
  @Test func theSessionsSinceADayAreTheOnesWithAHandleNewestFirst() throws {
    let database = try StoreDatabase.inMemory()
    let earlier = Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 - 86_400_000)
    let later = Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + 60_000)
    for (seed, at, handle) in [(10, earlier, "old"), (11, Fixture.instant, "a"), (12, later, "b"), (13, later, nil)] {
      try database.start(
        SessionRecord(
          id: Fixture.id(UInt64(seed)), owner: .panel("weather"), runtime: Runtime(provider: .claudeCode),
          handle: handle, instructions: "hash", startedAt: at))
    }

    #expect(try database.sessions(since: Fixture.instant).map(\.handle) == ["b", "a"])
  }

  @Test func aSessionFileIsFoundInTheFolderOfItsWorkingDirectory() throws {
    let folder = try ScratchFolder()
    defer { folder.remove() }
    let projects = folder.url.appending(path: "projects")
    let file = projects.appending(path: "-Users-x-Loci-agent/abc.jsonl")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{}\n".utf8).write(to: file)

    #expect(SessionFiles.find(in: [projects], depth: 1) { $0 == "abc.jsonl" }?.lastPathComponent == "abc.jsonl")
    #expect(SessionFiles.find(in: [projects], depth: 0) { $0 == "abc.jsonl" } == nil)
    #expect(SessionFiles.find(in: [folder.url.appending(path: "missing")], depth: 1) { _ in true } == nil)
    #expect(try SessionFiles.text(of: file) == "{}\n")
    #expect(SessionFiles.modified(file) != nil)
  }
}
