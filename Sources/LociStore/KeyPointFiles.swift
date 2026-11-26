import Foundation
import LociModel

/// `keypoints.json` in an item's folder: the key points picked for a video, an audio item or an article.
extension Store {
  static let keyPointsFile = "keypoints.json"

  public func keyPoints(of item: EntityID) throws -> KeyPoints? {
    try existing(itemFolder(item).appending(path: Self.keyPointsFile)).map { try decodeJSON(KeyPoints.self, at: $0) }
  }

  public func save(_ keyPoints: KeyPoints, of item: EntityID) throws {
    try write(Formats.document(keyPoints), to: itemFolder(item).appending(path: Self.keyPointsFile))
  }

  /// Forgets the key points, when none of them can be found in the text any more.
  public func removeKeyPoints(of item: EntityID) throws {
    guard let file = existing(try itemFolder(item).appending(path: Self.keyPointsFile)) else { return }
    try FileManager.default.removeItem(at: file)
  }
}
