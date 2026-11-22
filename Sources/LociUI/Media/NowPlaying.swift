import LociModel
import SwiftUI

/// The one thing playing in a window, a podcast episode or a video, kept by the window rather than its page,
/// so the sound goes on wherever the window goes: an episode in the play bar, a video left while playing in
/// the corner of the window or the system's picture in picture.
@MainActor
@Observable
final class NowPlaying {
  /// Where what plays shows, besides its own page.
  enum Presentation: Equatable {
    case none
    case bar
    case corner
    /// In the system's picture in picture, over every app.
    case system
  }

  private(set) var item: Item?
  private(set) var player: Player?
  private var inSystem = false

  /// Plays `item` on the player its page made, stopping whatever played before where it was.
  func play(_ item: Item, on player: Player) {
    if let current = self.player, current !== player { stop() }
    self.item = item
    self.player = player
    player.play()
  }

  /// The player of `item`, if it is what plays.
  func player(of item: EntityID) -> Player? {
    self.item?.id == item ? player : nil
  }

  /// Stops the sound, keeping where it got to.
  func stop() {
    player?.close()
    player = nil
    item = nil
    inSystem = false
  }

  /// The page of `item` was left: an episode goes on in the bar, a video goes on in the corner while it plays
  /// and stops when it does not.
  func left(_ item: EntityID) {
    guard self.item?.id == item, case .video = self.item?.kind, player?.playing != true else { return }
    stop()
  }

  /// The video went to the system's picture in picture, or came back from it.
  func handOver(toSystem: Bool) {
    inSystem = toSystem
  }

  /// How what plays shows while `front` is the item whose page is on top, if any.
  func presentation(front: EntityID?) -> Presentation {
    guard let item else { return .none }
    switch item.kind {
    case .audio: return .bar
    case .video: return inSystem ? .system : front == item.id ? .none : .corner
    case .article, .paper, .repository: return .none
    }
  }
}

extension EnvironmentValues {
  @Entry var nowPlaying: NowPlaying?
}
