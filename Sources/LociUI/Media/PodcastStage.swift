import LociModel
import SwiftUI

/// A podcast's page: the cover large with its glow, the title and show, the progress bar with the time
/// played and left, and the controls around a big play button.
struct PodcastStage: View {
  let model: StageModel

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        SquareCover(item: model.item, corner: 30)
          .padding(Size.podcastCover * 0.1)
          .blur(radius: 46)
          .saturation(1.4)
          .opacity(0.55)
        SquareCover(item: model.item, corner: Spacing.m)
          .overlay(
            RoundedRectangle(cornerRadius: Spacing.m, style: .continuous).strokeBorder(
              .black.opacity(0.15), lineWidth: Size.hairline)
          )
          .shadow(color: Color(nsColor: NSColor(rgb: 0x28140A)).opacity(0.3), radius: 25, y: 22)
          .shadow(color: .black.opacity(0.15), radius: 4, y: 3)
      }
      .frame(width: Size.podcastCover, height: Size.podcastCover)
      Text(serif: model.item.title, Typography.mediaTitle)
        .foregroundStyle(Palette.ink)
        .multilineTextAlignment(.center)
        .frame(maxWidth: Size.podcastColumn)
        .padding(.top, 28)
        .padding(.bottom, 6)
      if let show = model.item.site ?? model.item.authors.first {
        Text(verbatim: show).font(.system(size: 13)).foregroundStyle(Palette.inkMuted)
      }
      WhyLine(item: model.item, alignment: .center).frame(maxWidth: Size.podcastColumn).padding(.top, 8)
      Scrubber(
        timeline: model.timeline, time: model.player.time, onlyKeyPoints: model.onlyKeyPoints?.wrappedValue == true,
        seek: model.player.seek
      )
      .frame(width: Size.podcastColumn)
      .padding(.top, 22)
      HStack {
        Text(verbatim: MediaTime.text(model.player.time))
        Spacer()
        Text(verbatim: MediaTime.remaining(at: model.player.time, of: model.timeline.length))
      }
      .font(Typography.mono)
      .foregroundStyle(Palette.inkFaint)
      .frame(width: Size.podcastColumn)
      .padding(.top, 2)
      HStack(spacing: 14) {
        SpeedChip(player: model.player).frame(minWidth: 64)
        RoundIconButton(
          symbol: Symbols.back5, title: .loci("player.back"), size: Size.podcastButton, symbolSize: 21
        ) { model.player.skip(by: .seconds(-5)) }
        Button {
          model.player.toggle()
        } label: {
          Image(systemName: model.player.playing ? Symbols.pause : Symbols.play)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(Palette.canvas)
            .frame(width: Size.podcastPlay, height: Size.podcastPlay)
            .background(Circle().fill(Palette.ink).shadow(color: .black.opacity(0.18), radius: 8, y: 6))
        }
        .buttonStyle(PressStyle())
        .disabled(!model.player.canPlay)
        .accessibilityLabel(Text(model.player.playing ? .loci("player.pause") : .loci("player.play")))
        RoundIconButton(
          symbol: Symbols.forward5, title: .loci("player.forward"), size: Size.podcastButton, symbolSize: 21
        ) { model.player.skip(by: .seconds(5)) }
        SubtitleChip(model: model, symbol: false).frame(minWidth: 64)
      }
      .padding(.top, Spacing.s)
      if let only = model.onlyKeyPoints { OnlyKeyPointsPill(on: only).padding(.top, Spacing.s) }
    }
    .padding(.horizontal, 26)
    .padding(.top, 30)
    .padding(.bottom, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
