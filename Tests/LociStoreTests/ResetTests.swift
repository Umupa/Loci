import Foundation
import LociModel
import Testing

@testable import LociStore

struct ResetTests {
  @Test func everythingButTheSettingsIsDiscardedAsOneFolder() throws {
    let trash = FileManager.default.temporaryDirectory.appending(path: "loci-trash-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: trash) }
    let root = FileManager.default.temporaryDirectory.appending(path: "loci-store-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = Store(
      root: root,
      discard: Discard { url in
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: trash.appending(path: url.lastPathComponent))
      })
    try store.changeSettings { $0.runtime = Runtime(provider: .codex) }
    try store.writeFile("agent/MEMORY.md", "# Memory\n- 喜欢读论文\n")
    try store.writeFile("library/borg/item.json", "{}")
    try store.writeFile("loci.sqlite", "")

    try store.reset()

    let left = try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))
    #expect(left == [Store.settingsFile])
    #expect(try store.settings().runtime == Runtime(provider: .codex))
    let discarded = trash.appending(path: root.lastPathComponent)
    #expect(try String(contentsOf: discarded.appending(path: "agent/MEMORY.md"), encoding: .utf8).contains("论文"))
    #expect(FileManager.default.fileExists(atPath: discarded.appending(path: "library/borg/item.json").path()))
  }

  @Test func aFolderWithoutSettingsComesBackEmpty() throws {
    try withStore { store in
      try store.writeFile("agent/SOUL.md", "# Soul\n")

      try store.reset()

      #expect(try FileManager.default.contentsOfDirectory(atPath: store.root.path(percentEncoded: false)).isEmpty)
    }
  }

  @Test func nothingChangesWhenTheFolderCannotBeDiscarded() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "loci-store-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = Store(root: root, discard: Discard { _ in throw CocoaError(.fileWriteNoPermission) })
    try store.writeFile("agent/MEMORY.md", "# Memory\n")

    #expect(throws: CocoaError.self) { try store.reset() }

    #expect(try store.readFile("agent/MEMORY.md") == "# Memory\n")
  }
}
