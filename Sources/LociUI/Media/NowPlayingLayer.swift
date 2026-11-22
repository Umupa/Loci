import LociModel
import SwiftUI

extension View {
  /// Shows what plays in the window over the pages: an episode in the play bar along the foot, on a strip of
  /// its own that the pages scroll out of sight behind, a video left
  /// while playing in a corner; and tells the system about it. `open` brings an item's page to the front.
  func nowPlaying(
    _ nowPlaying: NowPlaying, items: [Item], front: EntityID?, open: @escaping (EntityID) -> Void
  ) -> some View {
    modifier(NowPlayingLayer(nowPlaying: nowPlaying, items: items, front: front, open: open))
  }
}

private struct NowPlayingLayer: ViewModifier {
  @Environment(\.covers) private var covers
  @Environment(\.standIns) private var standIns
  let nowPlaying: NowPlaying
  let items: [Item]
  let front: EntityID?
  let open: (EntityID) -> Void
  @State private var system: SystemNowPlaying?

  func body(content: Content) -> some View {
    let presentation = nowPlaying.presentation(front: front)
    content
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if presentation == .bar, let item = nowPlaying.item, let player = nowPlaying.player {
          PlayBar(episode: item, player: player, open: { open(item.id) }, close: nowPlaying.stop)
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.s)
            .frame(maxWidth: .infinity)
            .background(Palette.canvas)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .overlay {
        if presentation == .corner || presentation == .system, let item = nowPlaying.item,
          let player = nowPlaying.player
        {
          VideoCorner(
            item: item, player: player, inSystem: presentation == .system, open: { open(item.id) },
            close: nowPlaying.stop, handOver: nowPlaying.handOver(toSystem:)
          )
          .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
        }
      }
      .animation(Motion.standard, value: presentation)
      .onAppear {
        guard system == nil else { return }
        system = SystemNowPlaying(following: nowPlaying) { [covers] in covers?.image(of: $0) }
      }
      .onDisappear {
        nowPlaying.stop()
        system?.end()
        system = nil
      }
      .onChange(of: items.map(\.id)) { playAsAsked() }
  }

  /// Plays what a snapshot asks for, a third of the way in, once the items have arrived.
  private func playAsAsked() {
    guard let id = standIns?.listening, nowPlaying.item == nil, let item = items.first(where: { $0.id == id })
    else { return }
    let player = Player(start: (item.length ?? .zero) * 0.33, length: item.length)
    nowPlaying.play(item, on: player)
    player.showPlaying()
  }
}
