import CryptoKit
import Foundation
import LociModel
import Testing

@testable import LociStore

/// UP-S8: a patch brings a copy of the app to the next release, and the result is checked file by file.
struct AppPatchFilesTests {
  private static func sha(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  /// An app with a file that changes, one that goes, one that stays, a script, and a link that moves.
  private static func app(in support: Support) throws -> URL {
    let app = support.root.appending(path: "Loci (Beta).app")
    let files = FileManager.default
    try files.createDirectory(at: app.appending(path: "Contents/Old"), withIntermediateDirectories: true)
    try Data("1.1.1".utf8).write(to: app.appending(path: "Contents/version"))
    try Data("gone".utf8).write(to: app.appending(path: "Contents/Old/leftover"))
    try Data("same".utf8).write(to: app.appending(path: "Contents/same"))
    try Data("#!/bin/sh".utf8).write(to: app.appending(path: "Contents/tool"))
    try files.createSymbolicLink(atPath: app.appending(path: "Contents/current").path, withDestinationPath: "version")
    return app
  }

  private static func unpackedPatch(in support: Support, json: String) throws -> URL {
    let folder = try support.scratchFolder()
    try FileManager.default.createDirectory(
      at: folder.appending(path: "files/Contents/New"), withIntermediateDirectories: true)
    try Data("added".utf8).write(to: folder.appending(path: "files/Contents/New/added"))
    try Data(json.utf8).write(to: folder.appending(path: "patch.json"))
    return folder
  }

  private static let patch = """
    {"from": "1.1.1", "to": "1.2.0", "changed": [{"path": "Contents/version", "diff": "diffs/0"}],
     "added": ["Contents/New/added"], "removed": ["Contents/Old/leftover", "Contents/current"],
     "links": [{"path": "Contents/current", "target": "New/added"}]}
    """

  private static var manifest: String {
    """
    {"version": "1.2.0", "files": [
      {"path": "Contents/version", "sha256": "\(sha("1.2.0"))", "executable": false},
      {"path": "Contents/New/added", "sha256": "\(sha("added"))", "executable": false},
      {"path": "Contents/same", "sha256": "\(sha("same"))", "executable": false},
      {"path": "Contents/tool", "sha256": "\(sha("#!/bin/sh"))", "executable": true}],
     "links": [{"path": "Contents/current", "target": "New/added"}]}
    """
  }

  private static func patched(_ support: Support) throws -> (URL, AppManifest) {
    let app = try app(in: support)
    let unpacked = try unpackedPatch(in: support, json: patch)
    let rebuilt = support.root.appending(path: "rebuilt-0")
    try Data("1.2.0".utf8).write(to: rebuilt)
    let listing = support.root.appending(path: "files.json")
    try Data(manifest.utf8).write(to: listing)
    let manifest = try support.readManifest(listing)
    try support.apply(
      try support.readPatch(in: unpacked), unpackedIn: unpacked, rebuilt: ["Contents/version": rebuilt], to: app,
      manifest: manifest)
    return (app, manifest)
  }

  @Test func applyingAPatchChangesAddsRemovesAndLinksFiles() throws {
    try SupportTests.withSupport { support in
      let (app, manifest) = try Self.patched(support)
      try support.check(app, against: manifest)
      #expect(try String(contentsOf: app.appending(path: "Contents/version"), encoding: .utf8) == "1.2.0")
      #expect(try String(contentsOf: app.appending(path: "Contents/current"), encoding: .utf8) == "added")
      #expect(support.isExecutable(app.appending(path: "Contents/tool")))
      #expect(!FileManager.default.fileExists(atPath: app.appending(path: "Contents/Old").path))
    }
  }

  @Test(arguments: ["extra", "missing", "checksum", "runs", "link"])
  func aCopyIsCheckedAgainstEveryFileInTheManifest(damage: String) throws {
    try SupportTests.withSupport { support in
      let (app, manifest) = try Self.patched(support)
      let files = FileManager.default
      switch damage {
      case "extra": try Data("x".utf8).write(to: app.appending(path: "Contents/extra"))
      case "missing": try files.removeItem(at: app.appending(path: "Contents/same"))
      case "checksum": try Data("changed".utf8).write(to: app.appending(path: "Contents/same"))
      case "runs":
        try files.setAttributes([.posixPermissions: 0o644], ofItemAtPath: app.appending(path: "Contents/tool").path)
      default:
        try files.removeItem(at: app.appending(path: "Contents/current"))
        try files.createSymbolicLink(atPath: app.appending(path: "Contents/current").path, withDestinationPath: "same")
      }
      #expect(throws: PatchProblem.self) { try support.check(app, against: manifest) }
    }
  }

  @Test(arguments: ["../outside", "/etc/hosts", ""])
  func aPatchEntryOutsideTheAppIsRefused(path: String) throws {
    try SupportTests.withSupport { support in
      let json = """
        {"from": "1.1.1", "to": "1.2.0", "changed": [], "added": ["\(path)"], "removed": [], "links": []}
        """
      let unpacked = try Self.unpackedPatch(in: support, json: json)
      #expect(throws: PatchProblem.self) { try support.readPatch(in: unpacked) }
    }
  }

  @Test func thePreviousCopyIsKeptUntilTheNewVersionStarts() throws {
    try SupportTests.withSupport { support in
      let app = try Self.app(in: support)
      let release = AppRelease(
        version: ReleaseVersion("1.2.0")!, image: URL(string: "https://example.com/a.dmg")!,
        checksum: String(repeating: "0", count: 64))
      let files = UpdateFiles(support: support, identifier: "com.loci.native.dev", appName: "Loci (Beta).app")
      let previous = try files.keepPrevious(app, replacedBy: release)
      #expect(try String(contentsOf: previous.app.appending(path: "Contents/version"), encoding: .utf8) == "1.1.1")

      files.markStarted(ReleaseVersion("1.1.1")!)
      files.forgetPrevious()
      #expect(FileManager.default.fileExists(atPath: previous.app.path))

      files.markStarted(ReleaseVersion("1.2.0")!)
      files.forgetPrevious()
      #expect(!FileManager.default.fileExists(atPath: previous.folder.path))
      #expect(files.stagedUpdates().isEmpty)
    }
  }

  @Test func aCopyInTranslocationCannotUpdate() {
    let translocated = URL(filePath: "/private/var/folders/xy/T/AppTranslocation/1234/d/Loci (Beta).app")
    #expect(AppPlacement.of(translocated) == .translocated)
    #expect(AppPlacement.of(FileManager.default.temporaryDirectory) == .replaceable)
  }

  @Test func aCopyOnADiskImageCannotUpdate() throws {
    try SupportTests.withSupport { support in
      let source = support.root.appending(path: "image/Loci (Beta).app")
      try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
      let image = support.root.appending(path: "Loci.dmg")
      let mountPoint = support.root.appending(path: "mounted")
      try Self.hdiutil([
        "create", "-quiet", "-srcfolder", source.deletingLastPathComponent().path, "-format", "UDZO", image.path,
      ])
      try Self.hdiutil(["attach", "-quiet", "-nobrowse", "-noautoopen", "-mountpoint", mountPoint.path, image.path])
      defer { try? Self.hdiutil(["detach", "-quiet", "-force", mountPoint.path]) }
      #expect(AppPlacement.of(mountPoint.appending(path: "Loci (Beta).app")) == .diskImage)
      #expect(AppPlacement.of(source) == .replaceable)
    }
  }

  private static func hdiutil(_ arguments: [String]) throws {
    let program = Process()
    program.executableURL = URL(filePath: "/usr/bin/hdiutil")
    program.arguments = arguments
    try program.run()
    program.waitUntilExit()
    #expect(program.terminationStatus == 0)
  }
}
