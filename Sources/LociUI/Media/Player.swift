import AVFoundation
import LociModel

/// Plays one video or audio item and keeps the clock the rest of the page follows.
///
/// The clock starts where the reader left off, before anything has loaded, so the transcript and progress bar
/// show the right place at once. Where the reader is gets saved as they go: while playing, and on every pause
/// and jump.
@MainActor
@Observable
final class Player {
  enum Availability {
    case waiting, ready, failed
  }

  private(set) var availability = Availability.waiting
  var canPlay: Bool { availability == .ready }
  private(set) var time: Duration
  private(set) var playing = false
  private(set) var speed = PlaybackSpeed.normal
  /// From the media once it has loaded, or from the item until then.
  private(set) var length: Duration?
  /// No picture to show yet, or only the sound is playing, so the cover stays up.
  private(set) var soundOnly = true
  @ObservationIgnored private var streamsPicture = false
  let engine = AVPlayer()
  @ObservationIgnored private var ticking: Any?
  @ObservationIgnored private var watching: NSKeyValueObservation?
  @ObservationIgnored private var recovering: Task<Void, Never>?
  @ObservationIgnored private var savedAt = Duration.zero
  @ObservationIgnored private var finished = false
  @ObservationIgnored var remember: (Duration) -> Void = { _ in }
  @ObservationIgnored var reachedEnd: () -> Void = {}
  /// Asks the host for a fresh address after the site's one stopped working.
  @ObservationIgnored var refresh: () async -> PlayerSource? = { nil }
  /// What reads the bytes of media on another Mac. The asset holds its reader weakly, so the player keeps it.
  @ObservationIgnored private var ranged: RangedMedia?

  init(start: Duration, length: Duration?) {
    time = start
    self.length = length
  }

  /// Starts from where the clock is. A stream with headers sends them with every request.
  func load(_ source: PlayerSource) {
    load(source, refreshing: false)
  }

  private func load(_ source: PlayerSource, refreshing: Bool) {
    recovering?.cancel()
    recovering = nil
    let asset: AVURLAsset
    let canRefresh: Bool
    ranged = nil
    switch source {
    case .file(let file):
      asset = AVURLAsset(url: file.url)
      streamsPicture = true
      canRefresh = false
    case .ranges(let media):
      ranged = media
      asset = media.asset()
      streamsPicture = true
      canRefresh = false
    case .online(let stream):
      asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
      streamsPicture = !stream.audioOnly
      canRefresh = !refreshing
    }
    availability = .ready
    let item = AVPlayerItem(asset: asset)
    engine.replaceCurrentItem(with: item)
    engine.seek(to: Self.cmTime(time), toleranceBefore: .zero, toleranceAfter: .zero)
    if ticking == nil {
      ticking = engine.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: nil) {
        [weak self] moment in
        MainActor.assumeIsolated { self?.tick(moment) }
      }
    }
    soundOnly = true
    watching = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      let id = ObjectIdentifier(item)
      let failed = item.status == .failed
      let ready = item.status == .readyToPlay
      let seconds = item.duration.seconds
      MainActor.assumeIsolated {
        self?.settled(id, failed: failed, ready: ready, seconds: seconds, canRefresh: canRefresh)
      }
    }
    if playing { engine.rate = Float(speed.rawValue) }
  }

  func toggle() {
    playing ? pause() : play()
  }

  func play() {
    guard canPlay else { return }
    playing = true
    engine.rate = Float(speed.rawValue)
  }

  func pause() {
    playing = false
    engine.pause()
    save()
  }

  func seek(to moment: Duration) {
    let end = length ?? moment
    time = min(max(moment, .zero), end)
    engine.seek(to: Self.cmTime(time), toleranceBefore: .zero, toleranceAfter: .zero)
    save()
  }

  func skip(by distance: Duration) {
    seek(to: time + distance)
  }

  func faster() { set(speed.faster) }
  func slower() { set(speed.slower) }

  func set(_ speed: PlaybackSpeed) {
    self.speed = speed
    if playing { engine.rate = Float(speed.rawValue) }
  }

  /// Shows the controls as playing with nothing loaded, for a snapshot of the page.
  func showPlaying() {
    availability = .ready
    playing = true
  }

  /// Saves where the reader is and lets go of the media.
  func close() {
    save()
    engine.pause()
    if let ticking { engine.removeTimeObserver(ticking) }
    ticking = nil
    watching = nil
    recovering?.cancel()
    recovering = nil
    engine.replaceCurrentItem(with: nil)
    playing = false
    availability = .waiting
  }

  private func tick(_ moment: CMTime) {
    guard moment.isNumeric, engine.currentItem != nil else { return }
    time = .milliseconds(Int(moment.seconds * 1000))
    if playing, abs((time - savedAt).components.seconds) >= 10 { save() }
    if let length, time >= length - .seconds(1), !finished {
      finished = true
      reachedEnd()
    }
  }

  private func settled(_ id: ObjectIdentifier, failed: Bool, ready: Bool, seconds: Double, canRefresh: Bool) {
    guard engine.currentItem.map(ObjectIdentifier.init) == id else { return }
    if seconds.isFinite, seconds > 0 { length = .milliseconds(Int(seconds * 1000)) }
    if ready { soundOnly = !streamsPicture }
    guard failed else { return }
    guard canRefresh else {
      failedToPlay()
      return
    }
    guard recovering == nil else { return }
    recovering = Task { [weak self, refresh] in
      let fresh = await refresh()
      guard !Task.isCancelled, let self else { return }
      recovering = nil
      if let fresh {
        load(fresh, refreshing: true)
      } else {
        failedToPlay()
      }
    }
  }

  private func failedToPlay() {
    availability = .failed
    pause()
  }

  private func save() {
    savedAt = time
    remember(time)
  }

  private static func cmTime(_ duration: Duration) -> CMTime {
    CMTime(value: CMTimeValue(duration.roundedMilliseconds), timescale: 1000)
  }
}

/// What the player opens: a file on this Mac, media downloaded on another Mac, or the site's stream.
enum PlayerSource {
  case file(LocalFile)
  case ranges(RangedMedia)
  case online(OnlineStream)

  /// `nil` when the host can say neither where the file is nor how big it is.
  @MainActor
  static func of(_ playback: Playback, item: EntityID, on host: any LociModel.Host) async -> PlayerSource? {
    switch playback {
    case .downloaded:
      if let file = await host.localFile(.media(item)) { return .file(file) }
      guard let info = try? await host.run(ReadMediaFileInfo(item: item)) else { return nil }
      return RangedMedia(item: item, info: info, host: host).map(PlayerSource.ranges)
    case .online(let stream): return .online(stream)
    }
  }
}
