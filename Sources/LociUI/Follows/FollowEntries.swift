import AppKit
import LociModel
import SwiftUI

/// A follow's episodes, newest first: a channel's with their pictures, a show's as date, title and length. What
/// came since `seenBefore` has an amber dot and a fading amber line under it.
struct FollowEntries: View {
  let page: FollowPage
  let seenBefore: Timestamp
  @State private var shown = false

  var body: some View {
    let fresh = page.entries.prefix { $0.isNew(since: seenBefore) }.count
    LazyVStack(alignment: .leading, spacing: page.follow.source.isChannel ? Spacing.xs : 0) {
      ForEach(Array(page.entries.enumerated()), id: \.element.id) { index, entry in
        if fresh > 0, index == fresh {
          FreshSeam().padding(.vertical, Spacing.xs)
        }
        FollowEntryRow(entry: entry, follow: page.follow, isNew: index < fresh)
          .opacity(shown ? 1 : 0)
          .offset(y: shown ? 0 : Motion.riseDistance)
          .animation(Motion.arrive.delay(min(Double(index), 12) * 0.035), value: shown)
      }
    }
    .onAppear { shown = true }
  }
}

/// The line between what is new and what was seen.
private struct FreshSeam: View {
  var body: some View {
    LinearGradient(
      colors: [Palette.accent.opacity(0.7), Palette.accent.opacity(0)], startPoint: .leading, endPoint: .trailing
    )
    .frame(height: 1)
    .frame(maxWidth: 680)
  }
}

/// One episode: a click takes in one not in the library, through the import card, and opens one that is.
private struct FollowEntryRow: View {
  @Environment(\.takeIn) private var takeIn
  @Environment(\.openPage) private var openPage
  let entry: FollowPage.Entry
  let follow: Follow
  let isNew: Bool
  @State private var hovering = false

  var body: some View {
    Button(action: act) {
      HStack(alignment: .center, spacing: Spacing.m) {
        Circle()
          .fill(Palette.accent)
          .frame(width: 7, height: 7)
          .opacity(isNew ? 1 : 0)
          .frame(width: 10)
        if follow.source.isChannel { video } else { episode }
        Spacer(minLength: Spacing.s)
        action
      }
      .padding(.vertical, follow.source.isChannel ? 4 : 12)
      .padding(.trailing, Spacing.xs)
      .background(
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
          .fill(hovering ? Palette.fill : Color.clear)
          .padding(.horizontal, -Spacing.xs)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(Motion.quick, value: hovering)
    .disabled(entry.item == nil && takeIn == nil)
  }

  private var video: some View {
    HStack(alignment: .center, spacing: Spacing.m) {
      EpisodeThumbnail(episode: entry.episode, fallback: follow.picture)
        .flightMark(.episode(entry.episode.key))
      VStack(alignment: .leading, spacing: 6) {
        Text(serif: entry.episode.title, Typography.chapterTitle)
          .foregroundStyle(Palette.ink)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        if let published = entry.episode.published {
          EpisodeDate.day(published).font(Typography.caption).foregroundStyle(Palette.inkFaint)
        }
      }
    }
  }

  private var episode: some View {
    HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
      Text(verbatim: entry.episode.published.map { EpisodeDate.short($0) } ?? "")
        .font(Typography.clock)
        .foregroundStyle(Palette.inkFaint)
        .frame(width: 44, alignment: .leading)
      Text(serif: entry.episode.title, Typography.cardTitle)
        .foregroundStyle(Palette.ink)
        .lineLimit(1)
      Spacer(minLength: Spacing.s)
      Text(verbatim: entry.episode.length.map(MediaTime.text) ?? "")
        .font(Typography.clock)
        .foregroundStyle(Palette.inkFaint)
    }
    .flightMark(.episode(entry.episode.key))
  }

  @ViewBuilder private var action: some View {
    if entry.item != nil {
      Image(systemName: "checkmark.circle")
        .font(.system(size: 19, weight: .regular))
        .foregroundStyle(Palette.accent)
        .transition(.scale(scale: 0.4).combined(with: .opacity))
        .help(Text(.loci("follow.inLibrary")))
    } else {
      Image(systemName: Symbols.add)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(Palette.accentInk)
        .frame(width: 26, height: 26)
        .background(Circle().fill(Palette.accent))
        .opacity(hovering && takeIn != nil ? 1 : 0)
        .scaleEffect(hovering ? 1 : 0.7)
        .help(Text(.loci("follow.take")))
    }
  }

  private func act() {
    if let item = entry.item {
      openPage(.item(item))
    } else {
      takeIn?.link(entry.episode.link)
    }
  }
}
