import Foundation
import LociModel
import Testing

@testable import LociStore

struct SourceCacheTests {
  private let now = Timestamp(millisecondsSince1970: 2_000_000_000_000)
  private let day: Int64 = 86_400_000

  @Test func readingAgainGivesTheTextAnotherFourteenDays() throws {
    let cache = makeCache()
    defer { _ = try? cache.clear() }
    let key = SourceCache.Key.text(try #require(URL(string: "https://example.com/source")))
    let staging = try cache.stage(id: EntityID(), at: now)
    try cache.publish(text: "Full source\n", for: key, from: staging, at: now)
    #expect(try cache.text(for: key, at: later(13)) == "Full source\n")

    #expect(try !cache.purge(at: later(26)))
    #expect(try cache.purge(at: later(27)))
    #expect(try cache.text(for: key, at: later(27)) == nil)
  }

  @Test func aPreviouslyCachedExcerptCannotStandInForTheWholePage() throws {
    let cache = makeCache()
    defer { _ = try? cache.clear() }
    let url = try #require(URL(string: "https://example.com/long-specification"))
    let oldStage = try cache.stage(id: EntityID(), at: now)
    try cache.publish(text: "One section", for: .text(url), from: oldStage, at: now)

    #expect(try cache.text(for: .page(url), at: now) == nil)

    let newStage = try cache.stage(id: EntityID(), at: now)
    try cache.publish(text: "Every section", for: .page(url), from: newStage, at: now)
    #expect(try cache.text(for: .page(url), at: now) == "Every section")
  }

  @Test func pinnedCommitsHaveSeparateReadOnlyCheckoutsThatCanBeCleared() throws {
    let cache = makeCache()
    let manager = FileManager.default
    defer { _ = try? cache.clear() }
    let repo = try #require(URL(string: "https://example.com/repo"))
    let first = SourceCache.Key.repository(repo, try #require(CommitID(String(repeating: "a", count: 40))))
    let second = SourceCache.Key.repository(repo, try #require(CommitID(String(repeating: "b", count: 40))))
    let outside = manager.temporaryDirectory.appending(path: UUID().uuidString)
    try Data("untouched".utf8).write(to: outside)
    defer { try? manager.removeItem(at: outside) }

    for key in [first, second] {
      let staging = try cache.stage(id: EntityID(), at: now)
      let checkout = staging.url.appending(path: "checkout")
      try manager.createDirectory(at: checkout, withIntermediateDirectories: false)
      guard case .repository(_, let commit) = key else { return }
      try filesForCommit(commit, in: checkout)
      let executable = checkout.appending(path: "build")
      try Data("#!/bin/sh".utf8).write(to: executable)
      try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
      try manager.createSymbolicLink(at: checkout.appending(path: "link"), withDestinationURL: outside)
      _ = try cache.publishRepository(for: key, from: staging, at: now)
    }

    let checkout = try #require(try cache.repository(for: first, at: now))
    #expect(try cache.repository(for: second, at: now) != checkout)
    let mode = try manager.attributesOfItem(atPath: checkout.appending(path: "build").path)[.posixPermissions] as? Int
    #expect(mode == 0o555)
    #expect(try cache.bytes() > 0)
    #expect(try cache.clear())
    #expect(try cache.bytes() == 0)
    #expect(try String(contentsOf: outside, encoding: .utf8) == "untouched")
  }

  @Test func activeStagingIsKeptUntilItsOwnerLeaves() throws {
    let cache = makeCache()
    defer { _ = try? cache.clear() }
    var staging: SourceCache.Stage? = try cache.stage(id: EntityID(), at: now)
    let url = try #require(staging).url

    try withExtendedLifetime(staging) {
      let purged = try cache.purge(at: later(20))
      let cleared = try cache.clear()
      #expect(!purged)
      #expect(!cleared)
      #expect(FileManager.default.fileExists(atPath: url.path))
    }

    staging = nil
    #expect(try cache.purge(at: later(20)))
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test func clearingAndExpiringNeverCrossALinkedCacheRoot() throws {
    let files = FileManager.default
    let fixture = files.temporaryDirectory.appending(path: UUID().uuidString)
    let outside = fixture.appending(path: "outside")
    let root = fixture.appending(path: "cache")
    defer { try? files.removeItem(at: fixture) }
    let owner = SourceCache(root: outside)
    let key = SourceCache.Key.text(try #require(URL(string: "https://example.com/outside")))
    let stage = try owner.stage(id: EntityID(), at: now)
    try owner.publish(text: "Outside the cache", for: key, from: stage, at: now)
    try files.createSymbolicLink(at: root, withDestinationURL: outside)
    let cache = SourceCache(root: root)

    _ = try? cache.purge(at: later(20))
    _ = try? cache.clear()
    #expect((try? cache.text(for: key, at: now)) == nil)
    #expect(try owner.text(for: key, at: now) == "Outside the cache")
    #expect(throws: (any Error).self) { try cache.stage(id: EntityID(), at: now) }
  }

  @Test func clearingAndExpiringLeaveUnownedFoldersWhereTheyAre() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? files.removeItem(at: root) }
    let cache = SourceCache(root: root)
    let extra = root.appending(path: "repos/unrelated")
    let fakeHash = root.appending(path: "repos/" + String(repeating: "a", count: 64))
    let foreign = root.appending(path: "elsewhere")
    for folder in [extra, fakeHash, foreign] {
      try files.createDirectory(at: folder, withIntermediateDirectories: true)
      try Data("Keep this".utf8).write(to: folder.appending(path: "record"))
    }
    try files.createSymbolicLink(at: root.appending(path: ".staging"), withDestinationURL: foreign)

    _ = try? cache.purge(at: later(20))
    _ = try? cache.clear()

    for folder in [extra, fakeHash, foreign] {
      #expect(try String(contentsOf: folder.appending(path: "record"), encoding: .utf8) == "Keep this")
    }
  }

  @Test func aMissingOrCorruptBodyIsFetchedAndPublishedAgain() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? files.removeItem(at: root) }
    let cache = SourceCache(root: root)
    let key = SourceCache.Key.text(try #require(URL(string: "https://example.com/repair")))
    let first = try cache.stage(id: EntityID(), at: now)
    try cache.publish(text: "First body", for: key, from: first, at: now)
    let group = root.appending(path: "anonymous")
    let entry = try #require(files.contentsOfDirectory(at: group, includingPropertiesForKeys: nil).first)
    let body = entry.appending(path: "body")
    try files.removeItem(at: body)

    #expect(try cache.text(for: key, at: now) == nil)
    let second = try cache.stage(id: EntityID(), at: now)
    try cache.publish(text: "Restored body", for: key, from: second, at: now)
    #expect(try cache.text(for: key, at: now) == "Restored body")

    try Data([0xff]).write(to: body)
    #expect(try cache.text(for: key, at: now) == nil)
    let third = try cache.stage(id: EntityID(), at: now)
    try cache.publish(text: "Readable again", for: key, from: third, at: now)
    #expect(try cache.text(for: key, at: now) == "Readable again")
  }

  @Test func aCheckoutMissingFromItsCacheEntryIsPublishedAtAnExistingPath() throws {
    let cache = makeCache()
    let files = FileManager.default
    defer { _ = try? cache.clear() }
    let repo = try #require(URL(string: "https://example.com/repo"))
    let commit = try #require(CommitID(String(repeating: "a", count: 40)))
    let key = SourceCache.Key.repository(repo, commit)

    func prepare() throws -> SourceCache.Stage {
      let stage = try cache.stage(id: EntityID(), at: now)
      try filesForCommit(commit, in: stage.url.appending(path: "checkout"))
      return stage
    }

    let checkout = try cache.publishRepository(for: key, from: prepare(), at: now)
    for folder in [checkout, checkout.appending(path: ".git")] {
      try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
    }
    try files.removeItem(at: checkout)
    #expect(try cache.repository(for: key, at: now) == nil)
    let restored = try cache.publishRepository(for: key, from: prepare(), at: now)
    #expect(files.fileExists(atPath: restored.appending(path: ".git/HEAD").path))
    #expect(try cache.repository(for: key, at: now) != nil)

    let head = restored.appending(path: ".git/HEAD")
    try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: head.path)
    try Data(String(repeating: "b", count: 40).utf8).write(to: head)
    #expect(try cache.repository(for: key, at: now) == nil)
    _ = try cache.publishRepository(for: key, from: prepare(), at: now)
    #expect(try String(contentsOf: head, encoding: .utf8) == commit.description)
  }

  @Test func clearRemovesAbandonedStagingAsWellAsPublishedSources() throws {
    let cache = makeCache()
    let stage = try cache.stage(id: EntityID(), at: now).url
    defer { try? FileManager.default.removeItem(at: stage.deletingLastPathComponent().deletingLastPathComponent()) }
    try Data("Interrupted fetch".utf8).write(to: stage.appending(path: "info.json"))

    #expect(try cache.clear())
    #expect(!FileManager.default.fileExists(atPath: stage.path))
  }

  @Test func textSavedBeforeAnonymousFetchingIsInaccessibleAndRemoved() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? files.removeItem(at: root) }
    let cache = SourceCache(root: root)
    let key = SourceCache.Key.text(try #require(URL(string: "https://example.com/old-source")))
    let stage = try cache.stage(id: EntityID(), at: now)
    try cache.publish(text: "Old signed-in text", for: key, from: stage, at: now)
    let original = root.appending(path: "anonymous")
    let legacy = root.appending(path: "text")
    try files.moveItem(at: original, to: legacy)

    #expect(try cache.text(for: key, at: now) == nil)
    #expect(try cache.purge(at: now))
    #expect(try files.contentsOfDirectory(atPath: legacy.path).isEmpty)
  }

  private func filesForCommit(_ commit: CommitID, in checkout: URL) throws {
    try FileManager.default.createDirectory(at: checkout.appending(path: ".git"), withIntermediateDirectories: true)
    try Data(commit.description.utf8).write(to: checkout.appending(path: ".git/HEAD"))
  }

  private func makeCache() -> SourceCache {
    SourceCache(root: FileManager.default.temporaryDirectory.appending(path: "loci-source-cache-\(UUID())"))
  }

  private func later(_ days: Int64) -> Timestamp {
    Timestamp(millisecondsSince1970: now.millisecondsSince1970 + days * day)
  }
}
