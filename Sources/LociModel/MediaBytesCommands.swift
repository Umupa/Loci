import Foundation

/// How big a downloaded media file is and what kind, for a player that reads it in ranges.
public struct ReadMediaFileInfo: RemoteCommand {
  public static let name = "media.fileInfo"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> MediaFileInfo {
    try await handler.mediaFileInfo(of: item)
  }
}

/// Part of a downloaded media file. A range past the end gives the bytes up to the end.
public struct ReadMediaBytes: RemoteCommand {
  public static let name = "media.bytes"
  public let item: EntityID
  public let offset: Int64
  public let length: Int

  public init(item: EntityID, offset: Int64, length: Int) {
    self.item = item
    self.offset = offset
    self.length = length
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Data {
    try await handler.mediaBytes(self)
  }
}

public struct MediaFileInfo: Hashable, Codable, Sendable {
  public let byteCount: Int64
  /// The file's extension, such as `mp4` or `m4a`, from which a player knows its type.
  public let fileExtension: String

  public init(byteCount: Int64, fileExtension: String) {
    self.byteCount = byteCount
    self.fileExtension = fileExtension
  }
}
