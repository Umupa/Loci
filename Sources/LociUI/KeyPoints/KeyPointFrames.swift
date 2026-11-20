import AVFoundation
import AppKit
import LociModel

/// The video's picture at the start of each key point, drawn from the media the player has open.
@MainActor
@Observable
final class KeyPointFrames {
  private var images: [Duration: NSImage] = [:]
  @ObservationIgnored private var drawn: Set<Duration> = []

  func image(at time: Duration) -> NSImage? {
    images[time]
  }

  /// Draws the pictures at `times` not drawn yet, small enough for a thumbnail.
  func draw(_ times: [Duration], from asset: AVAsset) async {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 416, height: 234)
    generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 1)
    generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 1)
    for time in times where !drawn.contains(time) {
      drawn.insert(time)
      let moment = CMTime(value: CMTimeValue(time.roundedMilliseconds), timescale: 1000)
      let picture: CGImage? = await withCheckedContinuation { done in
        generator.generateCGImageAsynchronously(for: moment) { image, _, _ in done.resume(returning: image) }
      }
      guard let picture else { continue }
      images[time] = NSImage(cgImage: picture, size: NSSize(width: picture.width, height: picture.height))
    }
  }
}
