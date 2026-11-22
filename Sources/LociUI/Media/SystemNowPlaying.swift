import AppKit
import LociModel
import MediaPlayer

/// What the system shows of what plays, in Control Center and on the media keys' overlay.
struct NowPlayingCard: Equatable {
  let title: String
  /// The show or the channel.
  let artist: String?
  let length: Duration?
  let elapsed: Duration
  /// 0 while paused.
  let rate: Double

  init(title: String, artist: String?, length: Duration?, elapsed: Duration, rate: Double) {
    self.title = title
    self.artist = artist
    self.length = length
    self.elapsed = elapsed
    self.rate = rate
  }

  @MainActor
  init(item: Item, player: Player) {
    self.init(
      title: item.title, artist: item.site ?? item.authors.first, length: player.length ?? item.length,
      elapsed: player.time, rate: player.playing ? player.speed.rawValue : 0)
  }
}

/// Tells the system what a window plays, and takes its play, pause and skip commands, from Control Center and
/// the keyboard's media keys. The system moves the clock on by itself, so the card is sent again only when
/// what plays, whether it plays, its speed or its place jumps.
@MainActor
final class SystemNowPlaying {
  private let nowPlaying: NowPlaying
  private let cover: (EntityID) -> NSImage?
  private let center = MPNowPlayingInfoCenter.default()
  private var commands: [(MPRemoteCommand, Any)] = []

  init(following nowPlaying: NowPlaying, cover: @escaping (EntityID) -> NSImage?) {
    self.nowPlaying = nowPlaying
    self.cover = cover
    listen()
    follow()
  }

  /// Lets go of the commands and clears what the system shows.
  func end() {
    for (command, target) in commands { command.removeTarget(target) }
    commands = []
    center.nowPlayingInfo = nil
    center.playbackState = .stopped
  }

  private func follow() {
    withObservationTracking {
      show()
    } onChange: { [weak self] in
      Task { @MainActor in self?.follow() }
    }
  }

  private func show() {
    guard let item = nowPlaying.item, let player = nowPlaying.player else {
      center.nowPlayingInfo = nil
      center.playbackState = .stopped
      return
    }
    _ = player.jumps
    let card = NowPlayingCard(item: item, player: player)
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: card.title,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(card.elapsed.roundedMilliseconds) / 1000,
      MPNowPlayingInfoPropertyPlaybackRate: card.rate,
    ]
    if case .audio = item.kind {
      info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
    } else {
      info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
    }
    if let artist = card.artist { info[MPMediaItemPropertyArtist] = artist }
    if let length = card.length {
      info[MPMediaItemPropertyPlaybackDuration] = Double(length.roundedMilliseconds) / 1000
    }
    if let image = cover(item.id) {
      info[MPMediaItemPropertyArtwork] = Self.artwork(image)
    }
    center.nowPlayingInfo = info
    center.playbackState = card.rate > 0 ? .playing : .paused
  }

  /// The system asks for the picture on its own queue.
  private nonisolated static func artwork(_ image: NSImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
  }

  private func listen() {
    let remote = MPRemoteCommandCenter.shared()
    on(remote.playCommand) { $0.player?.play() }
    on(remote.pauseCommand) { $0.player?.pause() }
    on(remote.togglePlayPauseCommand) { $0.player?.toggle() }
    remote.skipForwardCommand.preferredIntervals = [30]
    remote.skipBackwardCommand.preferredIntervals = [15]
    on(remote.skipForwardCommand) { $0.player?.skip(by: .seconds(30)) }
    on(remote.skipBackwardCommand) { $0.player?.skip(by: .seconds(-15)) }
    let seek = remote.changePlaybackPositionCommand
    let target = seek.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      let time = Duration.milliseconds(Int(event.positionTime * 1000))
      return MainActor.assumeIsolated {
        guard let player = self?.nowPlaying.player else { return .noActionableNowPlayingItem }
        player.seek(to: time)
        return .success
      }
    }
    commands.append((seek, target))
  }

  private func on(_ command: MPRemoteCommand, _ act: @escaping @MainActor (NowPlaying) -> Void) {
    let target = command.addTarget { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.nowPlaying.player != nil else { return .noActionableNowPlayingItem }
        act(self.nowPlaying)
        return .success
      }
    }
    commands.append((command, target))
  }
}
