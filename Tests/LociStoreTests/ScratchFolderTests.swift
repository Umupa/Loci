import Foundation
import Testing

@testable import LociStore

struct ScratchFolderTests {
  @Test func aScratchFolderStartsEmptyAndIsGoneWhenRemoved() throws {
    let folder = try ScratchFolder()
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path(percentEncoded: false)).isEmpty)
    let another = try ScratchFolder()
    defer { another.remove() }
    #expect(another.url != folder.url)

    folder.remove()

    #expect(!FileManager.default.fileExists(atPath: folder.url.path(percentEncoded: false)))
  }
}
