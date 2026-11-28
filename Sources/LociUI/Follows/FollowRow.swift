import AppKit
import LociModel
import SwiftUI

/// The follows above the video or podcast gallery, the most recently updated first, and a dashed `+` at the end
/// that puts the keyboard in the link field. A follow with an episode the person has not seen has an amber dot;
/// resting the pointer on it shows the newest.
struct FollowRow: View {
  let follows: [FollowSummary]
  let add: () -> Void
  let open: (Follow) -> Void
  let stop: (Follow) -> Void

  static let side: CGFloat = 64
  static let width: CGFloat = 88

  var body: some View {
    ScrollView(.horizontal) {
      HStack(alignment: .top, spacing: Spacing.s) {
        ForEach(follows) { summary in
          FollowBadge(summary: summary, open: { open(summary.follow) }, stop: { stop(summary.follow) })
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
        AddFollowBadge(isChannel: follows.first?.follow.source.isChannel ?? true, add: add)
      }
      .padding(.vertical, 6)
      .animation(Motion.standard, value: follows.map(\.id))
    }
    .scrollIndicators(.never)
    .scrollClipDisabled()
  }
}

private struct FollowBadge: View {
  @Environment(\.flights) private var flights
  @Environment(\.changesAllowed) private var changesAllowed
  let summary: FollowSummary
  let open: () -> Void
  let stop: () -> Void
  @State private var hovering = false
  @State private var peeking = false

  private var follow: Follow { summary.follow }

  var body: some View {
    Button(action: open) {
      VStack(spacing: 7) {
        FollowFace(picture: follow.picture, isChannel: follow.source.isChannel, side: FollowRow.side)
          .flightMark(.follow(follow.id))
          .opacity(flights?.isLanding(on: .follow(follow.id)) == true ? 0 : 1)
          .scaleEffect(hovering ? 1.04 : 1)
          .overlay(alignment: .topTrailing) {
            if !summary.fresh.isEmpty {
              Circle()
                .fill(Palette.accent)
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(Palette.canvas, lineWidth: 2))
                .offset(x: follow.source.isChannel ? -2 : 3, y: follow.source.isChannel ? 2 : -3)
                .transition(.scale.combined(with: .opacity))
            }
          }
        Text(verbatim: follow.name)
          .font(.system(size: 11.5))
          .foregroundStyle(Palette.inkMuted)
          .lineLimit(1)
          .frame(width: FollowRow.width)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .animation(Motion.quick, value: hovering)
    .animation(Motion.rise, value: summary.fresh.isEmpty)
    .onHover { hovering = $0 }
    .task(id: hovering) {
      guard hovering, !summary.fresh.isEmpty else {
        peeking = false
        return
      }
      try? await Task.sleep(for: .milliseconds(550))
      if !Task.isCancelled { peeking = true }
    }
    .popover(isPresented: $peeking, arrowEdge: .bottom) { FollowPeek(summary: summary) }
    .contextMenu {
      Button(.loci("follow.open"), action: open)
      Link(destination: follow.page) { Text(.loci("follow.openInBrowser")) }
      if changesAllowed {
        Divider()
        Button(.loci("follow.stop"), role: .destructive, action: stop)
      }
    }
  }
}

/// The dashed place at the end of the row: following someone starts with a link.
private struct AddFollowBadge: View {
  let isChannel: Bool
  let add: () -> Void
  @State private var hovering = false

  var body: some View {
    let side = FollowRow.side
    let shape = FollowFace.shape(side: side, rounding: FollowFace.rounding(isChannel))
    Button(action: add) {
      VStack(spacing: 7) {
        Image(systemName: Symbols.add)
          .font(.system(size: 18, weight: .light))
          .foregroundStyle(hovering ? Palette.accentInk : Palette.inkFaint)
          .frame(width: side, height: side)
          .overlay(
            shape.strokeBorder(
              hovering ? Palette.accent : Palette.lineStrong, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])))
        Text(verbatim: " ").font(.system(size: 11.5))
      }
      .frame(width: FollowRow.width)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .animation(Motion.quick, value: hovering)
    .help(Text(.loci("follow.add")))
  }
}

/// What came out since the person last looked: the newest, and the others after it.
struct FollowPeek: View {
  let summary: FollowSummary

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if let newest = summary.fresh.first {
        if summary.follow.source.isChannel {
          EpisodeThumbnail(episode: newest, fallback: summary.follow.picture, width: 246)
        }
        Text(serif: newest.title, Typography.cardTitle)
          .foregroundStyle(Palette.ink)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
        EpisodeMeta(episode: newest)
        if summary.fresh.count > 1 {
          if summary.follow.source.isChannel {
            HStack(spacing: 6) {
              ForEach(summary.fresh.dropFirst().prefix(3), id: \.key) { episode in
                EpisodeThumbnail(episode: episode, fallback: summary.follow.picture, width: 76)
              }
            }
          } else {
            ForEach(summary.fresh.dropFirst().prefix(2), id: \.key) { episode in
              Text(verbatim: episode.title).font(Typography.body).foregroundStyle(Palette.inkMuted).lineLimit(2)
            }
          }
        }
      }
    }
    .padding(Spacing.s)
    .frame(width: 270, alignment: .leading)
  }
}

/// `45:10 · 11月24日`.
struct EpisodeMeta: View {
  let episode: Episode

  var body: some View {
    HStack(spacing: 5) {
      if let length = episode.length { Text(verbatim: MediaTime.text(length)).font(Typography.clock) }
      if episode.length != nil, episode.published != nil { Text(verbatim: "·") }
      if let published = episode.published { EpisodeDate.day(published) }
    }
    .font(Typography.caption)
    .foregroundStyle(Palette.inkFaint)
  }
}
