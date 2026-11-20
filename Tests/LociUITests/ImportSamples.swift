import Foundation
import LociModel

/// Links the import panel reads in snapshots, as the design draws them.
enum ImportSamples {
  static let video = URL(string: "https://www.youtube.com/watch?v=O_zcc6Xl12g")!
  static let episode = URL(string: "https://podcasts.apple.com/us/podcast/x/id1?i=2")!
  /// A link that is never read, so the panel keeps its placeholders.
  static let slow = URL(string: "https://www.youtube.com/watch?v=slow")!

  static let previews: [URL: MediaPreview] = [
    video: MediaPreview(
      title: "AI Code Is Ugly (Except Mine)", site: "Laurie Voss", duration: .seconds(962),
      cover: SampleLibrary.picture("kube"), isAudio: false,
      sizes: [.hd1080: 412_000_000, .hd720: 198_000_000, .audio: 15_400_000], subtitles: ["en", "ja"],
      spokenSubtitles: "en"),
    episode: MediaPreview(
      title: "The Inference Bottleneck", site: "Latent Space", duration: .seconds(4360),
      cover: SampleLibrary.picture("latent"), isAudio: true, sizes: [.audio: 66_000_000], subtitles: [],
      spokenSubtitles: nil),
  ]
}
