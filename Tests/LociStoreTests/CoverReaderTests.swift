import Foundation
import LociModel
import Testing

@testable import LociStore

struct CoverReaderTests {
  @Test func aCoverReaderFollowsTheItemWhenItsFolderMoves() async throws {
    let store = temporaryStore()
    defer { try? FileManager.default.removeItem(at: store.root) }
    let item = try Fixture.item()
    let original = Data("original".utf8)
    try store.add(item, content: "text")
    try store.saveCover(original, extension: "png", of: item.id)
    let reader = CoverReader(store)

    #expect(try await reader.cover(of: item.id) == original)
    let folder = try store.itemFolder(item.id)
    try FileManager.default.moveItem(at: folder, to: store.libraryFolder.appending(path: "manually-renamed"))
    let replacement = try Fixture.item(3)
    try store.write(Formats.document(replacement), to: folder.appending(path: Store.itemFile))
    try store.write(Data("unrelated".utf8), to: folder.appending(path: "cover.png"))

    #expect(try await reader.cover(of: item.id) == original)
  }

  @Test func aCoverReaderSeesTheCoverAppearAndChange() async throws {
    let store = temporaryStore()
    defer { try? FileManager.default.removeItem(at: store.root) }
    let item = try Fixture.item()
    try store.add(item, content: "text")
    let reader = CoverReader(store)
    #expect(try await reader.cover(of: item.id) == nil)

    let first = Data("first".utf8)
    try store.saveCover(first, extension: "png", of: item.id)
    #expect(try await reader.cover(of: item.id) == first)

    let next = Data("next".utf8)
    try store.saveCover(next, extension: "jpg", of: item.id)
    #expect(try await reader.cover(of: item.id) == next)
  }
}
