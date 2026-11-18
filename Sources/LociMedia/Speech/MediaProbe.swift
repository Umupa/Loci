import AVFoundation
import Foundation

/// What a local media file holds, for an item made from it.
public struct MediaProbe: Hashable, Sendable {
  /// `nil` when the file does not say.
  public let duration: Duration?
  public let hasPicture: Bool
  public let hasSound: Bool

  public init(duration: Duration?, hasPicture: Bool, hasSound: Bool) {
    self.duration = duration
    self.hasPicture = hasPicture
    self.hasSound = hasSound
  }

  /// Reads the file's tracks and length; `nil` when AVFoundation cannot open it.
  public static func of(_ url: URL) async -> MediaProbe? {
    let asset = AVURLAsset(url: url)
    guard let time = try? await asset.load(.duration),
      let pictures = try? await asset.loadTracks(withMediaType: .video),
      let sounds = try? await asset.loadTracks(withMediaType: .audio)
    else { return nil }
    let seconds = time.seconds
    return MediaProbe(
      duration: seconds.isFinite && seconds > 0 ? .milliseconds(Int(seconds * 1000)) : nil,
      hasPicture: !pictures.isEmpty, hasSound: !sounds.isEmpty)
  }
}
