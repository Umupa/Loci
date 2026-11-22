import LociModel
import SwiftUI

/// The episode playing, along the foot of the window wherever it goes: its cover and title, which bring the
/// episode back, the controls, and how far it has got. Closing it stops the sound.
struct PlayBar: View {
  let episode: Item
  let player: Player
  let open: () -> Void
  let close: () -> Void

  var body: some View {
    HStack(spacing: Spacing.s) {
      Button(action: open) {
        HStack(spacing: Spacing.s) {
          SquareCover(item: episode, corner: Radius.thumbnail)
            .frame(width: Size.playBarCover, height: Size.playBarCover)
            .overlay(
              RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                .strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: episode.title)
              .font(Typography.bodyEmphasis)
              .foregroundStyle(Palette.ink)
            if let show = episode.site ?? episode.authors.first {
              Text(verbatim: show).font(Typography.caption).foregroundStyle(Palette.inkMuted)
            }
          }
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(PressStyle())
      .help(Text(verbatim: episode.title))
      HStack(spacing: 2) {
        RoundIconButton(symbol: Symbols.back15, title: .loci("player.skipBack"), symbolSize: 15) {
          player.skip(by: .seconds(-15))
        }
        RoundIconButton(
          symbol: player.playing ? Symbols.pause : Symbols.play,
          title: player.playing ? .loci("player.pause") : .loci("player.play"), size: 36, symbolSize: 19
        ) { player.toggle() }
        .disabled(!player.canPlay)
        .contentTransition(.symbolEffect(.replace))
        RoundIconButton(symbol: Symbols.forward30, title: .loci("player.skipForward"), symbolSize: 15) {
          player.skip(by: .seconds(30))
        }
      }
      SpeedChip(player: player)
      RoundIconButton(symbol: Symbols.cancel, title: .loci("player.close"), size: 26, symbolSize: 11, action: close)
    }
    .padding(.leading, Spacing.xs)
    .padding(.trailing, Spacing.s)
    .frame(maxWidth: Size.playBar.width, minHeight: Size.playBar.height)
    .overlay(alignment: .bottom) {
      PlayedLine(share: share).padding(.horizontal, Radius.card)
    }
    .background(Palette.canvas.opacity(0.94), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
  }

  private var share: Double {
    guard let length = player.length ?? episode.length, length > .zero else { return 0 }
    return min(max(Double(player.time.roundedMilliseconds) / Double(length.roundedMilliseconds), 0), 1)
  }
}

/// How much of an episode has played, as a hairline along the bar's foot.
private struct PlayedLine: View {
  let share: Double

  var body: some View {
    GeometryReader { frame in
      Capsule().fill(Palette.accent).frame(width: frame.size.width * share)
    }
    .frame(height: 2)
    .background(Capsule().fill(Palette.fillStrong))
    .accessibilityHidden(true)
  }
}
