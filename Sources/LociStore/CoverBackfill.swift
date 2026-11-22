import Foundation
import LociModel

extension Store {
  private var coverBackfillMarker: URL {
    root.appending(path: ".covers-backfilled")
  }

  public var didBackfillCovers: Bool {
    FileManager.default.fileExists(atPath: coverBackfillMarker.path(percentEncoded: false))
  }

  public func foldersForCoverBackfill() -> [URL]? {
    didBackfillCovers ? nil : subfolders(of: libraryFolder)
  }

  public func itemForCoverBackfill(in folder: URL) -> Item? {
    try? decodeJSON(Item.self, at: folder.appending(path: Self.itemFile))
  }

  public func markCoversBackfilled() throws {
    try write(Data(), to: coverBackfillMarker)
  }
}
