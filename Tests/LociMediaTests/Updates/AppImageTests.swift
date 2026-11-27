import Foundation
import LociMedia
import LociModel
import Testing

/// UP-S8 and UP-S10, with the real programs: `bspatch` rebuilds a file, and the watcher puts the previous copy
/// back only when the new one quits before it starts.
@Suite(.timeLimit(.minutes(1)))
struct AppImageTests {
  @Test func bspatchRebuildsTheNewFile() async throws {
    let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let folder = try Place()
    let rebuilt = folder.url.appending(path: "rebuilt.txt")
    try await AppImage(runner: SystemRunner()).rebuild(
      fixtures.appending(path: "update-old.txt"), into: rebuilt, with: fixtures.appending(path: "update.bsdiff"))
    #expect(try Data(contentsOf: rebuilt) == Data(contentsOf: fixtures.appending(path: "update-new.txt")))
  }

  @Test func aDamagedPatchFails() async throws {
    let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let folder = try Place()
    let damaged = folder.url.appending(path: "damaged.bsdiff")
    try Data("BSDIFF40 not really".utf8).write(to: damaged)
    await #expect(throws: FetchError.self) {
      try await AppImage(runner: SystemRunner()).rebuild(
        fixtures.appending(path: "update-old.txt"), into: folder.url.appending(path: "out"), with: damaged)
    }
  }

  @Test func theGuardPutsThePreviousCopyBackWhenTheNewOneExitsBeforeStarting() async throws {
    let place = try Place()
    let copy = try place.updated()
    try await copy.watch(opens: false)
    let running = try await copy.run(for: 1)
    try await running.value
    try await place.eventually {
      !FileManager.default.fileExists(atPath: copy.previous.folder.path(percentEncoded: false))
    }
    #expect(try copy.installedSays() == "old")
    #expect(FileManager.default.fileExists(atPath: copy.previous.record.path(percentEncoded: false)))
    #expect(try String(contentsOf: copy.previous.failed.appending(path: "marker"), encoding: .utf8) == "new")
  }

  @Test func theGuardKeepsTheNewCopyOnceItStarts() async throws {
    let place = try Place()
    let copy = try place.updated()
    try await copy.watch(opens: false)
    let running = try await copy.run(for: 2)
    try Data().write(to: copy.previous.started)
    try await running.value
    try await place.eventually {
      !FileManager.default.fileExists(atPath: copy.previous.folder.path(percentEncoded: false))
    }
    #expect(try copy.installedSays() == "new")
    #expect(!FileManager.default.fileExists(atPath: copy.previous.record.path(percentEncoded: false)))
  }

  @Test func aSlowStartIsNotRolledBack() async throws {
    let place = try Place()
    let copy = try place.updated()
    try await copy.watch(opens: false, appearing: .seconds(1))
    let running = try await copy.run(for: 4)
    try await Task.sleep(for: .seconds(2.5))
    #expect(try copy.installedSays() == "new")
    try Data().write(to: copy.previous.started)
    try await running.value
    try await place.eventually {
      !FileManager.default.fileExists(atPath: copy.previous.folder.path(percentEncoded: false))
    }
    #expect(try copy.installedSays() == "new")
  }

  @Test func anOpenedCopyThatNeverRunsIsRolledBack() async throws {
    let place = try Place()
    let copy = try place.updated()
    try await copy.watch(opens: true, appearing: .seconds(1))
    try await place.eventually {
      FileManager.default.fileExists(atPath: copy.previous.record.path(percentEncoded: false))
    }
    #expect(try copy.installedSays() == "old")
  }
}

/// A temporary folder holding an app just updated from `old` to `new`, and the previous copy kept for it.
private struct Place {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory.appending(path: "loci-image-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  func updated() throws -> UpdatedCopy {
    let updates = url.appending(path: "updates")
    let folder = updates.appending(path: "previous")
    let previous = PreviousCopy(
      folder: folder, app: folder.appending(path: "Loci (Beta).app"), release: folder.appending(path: "release.json"),
      started: folder.appending(path: "started"), failed: updates.appending(path: "failed"),
      record: updates.appending(path: "rolled-back.json"))
    let app = url.appending(path: "Applications/Loci (Beta).app")
    for (copy, says) in [(app, "new"), (previous.app, "old")] {
      try FileManager.default.createDirectory(
        at: copy.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
      try Data(says.utf8).write(to: copy.appending(path: "marker"))
    }
    try Data("{}".utf8).write(to: previous.release)
    return UpdatedCopy(app: app, previous: previous)
  }

  func eventually(_ condition: () throws -> Bool) async throws {
    for _ in 0..<100 {
      if (try? condition()) == true { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    Issue.record("the watcher did not get there in ten seconds")
  }
}

private struct UpdatedCopy {
  let app: URL
  let previous: PreviousCopy

  /// Starts the watcher after a process that has already ended, opening with `true` in place of `open`.
  func watch(opens: Bool, appearing: Duration = .seconds(5)) async throws {
    try await AppImage(runner: SystemRunner(), opener: "/usr/bin/true").watchStart(
      of: app, previous: previous, after: 999_999, opens: opens, appearing: appearing)
  }

  /// A process that runs as the new copy's executable for `seconds`, already running when this returns.
  func run(for seconds: Int) async throws -> Task<Void, any Error> {
    let executable = app.appending(path: "Contents/MacOS/Loci").path(percentEncoded: false)
    let call = ProgramCall(
      executable: URL(filePath: "/bin/bash"), arguments: ["-c", "exec -a \"$0\" /bin/sleep \(seconds)", executable])
    let running = Task { _ = try await SystemRunner().run(call) }
    try await Task.sleep(for: .milliseconds(300))
    return running
  }

  func installedSays() throws -> String {
    try String(contentsOf: app.appending(path: "marker"), encoding: .utf8)
  }
}
