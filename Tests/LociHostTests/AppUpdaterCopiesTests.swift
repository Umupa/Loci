import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// Copies with different bundle identifiers keep their update files apart, so a test copy never holds back or
/// takes up the published one's update; the published copy clears what releases up to 1.8.8 left behind.
@Suite(.timeLimit(.minutes(1)))
struct AppUpdaterCopiesTests {
  private static let testCopy = "fun.loci.bbtest.update"

  @Test func aCopyWithAnotherIdentifierDoesNotTakeUpAStagedUpdate() async throws {
    let published = try UpdateWorld(latest: "v1.2.0")
    try await published.downloadLatest()
    let test = try UpdateWorld(latest: "v1.2.0", identifier: Self.testCopy, folder: published.folder)
    test.network.offline = true
    await test.launch()
    #expect(await test.state() == .current)
    #expect(test.stagedFolders.isEmpty)
    #expect(published.stagedFolders == ["1.2.0"])
  }

  @Test func aRollBackOfOneCopyDoesNotHoldBackAnother() async throws {
    let test = try UpdateWorld(latest: "v1.2.0", identifier: Self.testCopy)
    try await test.downloadLatest()
    await test.updater.restart()
    try test.rollBack()

    let published = try UpdateWorld(latest: "v1.2.0", folder: test.folder)
    await published.launch()
    #expect(await published.state() == .ready(published.release))
    let again = try UpdateWorld(latest: "v1.2.0", identifier: Self.testCopy, folder: test.folder)
    await again.launch()
    #expect(await again.state() == .failed(again.release, .launch))
  }

  @Test func thePublishedCopyRemovesWhatEarlierReleasesLeftInTheSharedFolder() async throws {
    let world = try UpdateWorld(latest: "v1.1.1")
    let leftovers = try Self.leaveEarlierLayout(in: world)
    await world.launch()
    for leftover in leftovers {
      #expect(!FileManager.default.fileExists(atPath: leftover.path(percentEncoded: false)))
    }
  }

  @Test func aTestCopyLeavesTheSharedFolderAlone() async throws {
    let world = try UpdateWorld(latest: "v1.1.1", identifier: Self.testCopy)
    let leftovers = try Self.leaveEarlierLayout(in: world)
    await world.launch()
    for leftover in leftovers {
      #expect(FileManager.default.fileExists(atPath: leftover.path(percentEncoded: false)))
    }
  }

  @Test(arguments: ["patch", "archive", "image", "fallback"])
  func updatingWritesNothingOutsideThisCopysUpdateFolder(path: String) async throws {
    let world = try UpdateWorld(latest: "v1.2.0", identifier: Self.testCopy)
    switch path {
    case "patch": world.offerPatch()
    case "archive": world.network.offers.archive = UpdatePrograms.archive(["Loci (Beta).app/marker": "whole"])
    case "fallback":
      world.offerPatch()
      world.programs.rebuilds = false
    default: break
    }
    try await world.downloadLatest()
    #expect(await world.state() == .ready(world.release))
    let inside = world.updates.path(percentEncoded: false)
    for written in world.programs.writtenPaths {
      #expect(written.hasPrefix(inside), "\(written) is outside \(inside)")
    }
    #expect(!world.programs.writtenPaths.isEmpty)
    #expect(Self.everything(in: world.support).allSatisfy { $0.hasPrefix(inside) || inside.hasPrefix($0) })
  }

  /// Every file and folder under `folder`, as paths with a trailing slash for folders.
  private static func everything(in folder: URL) -> [String] {
    let root = folder.path(percentEncoded: false)
    let walk = FileManager.default.enumerator(atPath: root)
    return (walk?.allObjects as? [String] ?? []).map { relative in
      var isFolder: ObjCBool = false
      let full = folder.appending(path: relative).path(percentEncoded: false)
      FileManager.default.fileExists(atPath: full, isDirectory: &isFolder)
      return isFolder.boolValue && !full.hasSuffix("/") ? full + "/" : full
    }
  }

  /// What 1.8.8 can leave in `updates/`: a staged copy never put in place and a download that never finished.
  private static func leaveEarlierLayout(in world: UpdateWorld) throws -> [URL] {
    let updates = world.support.appending(path: "updates")
    let staged = updates.appending(path: "1.1.2")
    try FileManager.default.createDirectory(
      at: staged.appending(path: "Loci (Beta).app"), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: staged.appending(path: "release.json"))
    let partial = updates.appending(path: "\(String(repeating: "a", count: 64)).partial")
    try Data("dm".utf8).write(to: partial)
    return [staged, partial]
  }
}
