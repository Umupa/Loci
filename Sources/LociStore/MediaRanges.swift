import Foundation
import LociModel

extension Store {
  /// The size and kind of the item's media, for a player that reads it in ranges; `nil` until there is one.
  public func mediaFileInfo(of item: EntityID) throws -> MediaFileInfo? {
    guard let file = try mediaFile(of: item) else { return nil }
    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    return MediaFileInfo(byteCount: Int64(size), fileExtension: file.pathExtension)
  }

  /// Up to `length` bytes of the item's media from `offset`; fewer at the end of the file, none past it.
  public func mediaBytes(of item: EntityID, offset: Int64, length: Int) throws -> Data {
    guard let file = try mediaFile(of: item) else { throw StoreError.notFound("media of \(item)") }
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    try handle.seek(toOffset: UInt64(max(0, offset)))
    return try handle.read(upToCount: max(0, length)) ?? Data()
  }
}
