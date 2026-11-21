import LociModel
import SwiftUI

/// A list in a panel: each line on its own faint block, opening its link when clicked.
struct PanelList: View {
  let items: [PanelListItem]
  let actions: PanelActions

  var body: some View {
    VStack(spacing: Spacing.xs) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        PanelLine(
          title: item.title, subtitle: item.subtitle, at: item.at, number: item.number, progress: item.progress,
          ask: item.ask.map { words in { actions.ask(words) } },
          open: item.link.map { link in { actions.open(link) } }
        ) {
          if let cover = item.cover { PanelCover(url: cover) }
        }
      }
    }
  }
}

/// One line of a list, as both Loci's panels and 「接着读」 draw it: a rank, a cover, the title over a subtitle
/// and a progress bar, when it happened, and 「问 Loci」.
struct PanelLine<Cover: View>: View {
  let title: String
  var subtitle: String?
  var at: String?
  var number: Int?
  var progress: Double?
  var ask: (() -> Void)?
  var open: (() -> Void)?
  @ViewBuilder var cover: Cover
  @State private var pointed = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.panelBlock, style: .continuous)
    HStack(alignment: .top, spacing: 10) {
      if let number {
        Text(verbatim: "\(number)").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink.opacity(0.35))
          .frame(width: 18, alignment: .leading)
      }
      cover
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: title).font(.system(size: 14)).lineSpacing(2).foregroundStyle(Palette.ink)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(verbatim: subtitle).font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
        }
        if let progress { PanelProgress(progress: progress).padding(.top, 5) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if let at {
        Text(verbatim: at).font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.45)).padding(.top, 1)
      }
      if let ask { AskButton(action: ask) }
    }
    .padding(.vertical, 11)
    .padding(.horizontal, Spacing.s)
    .background(Palette.ink.opacity(pointed && open != nil ? 0.08 : 0.05), in: shape)
    .contentShape(shape)
    .onHover { pointed = $0 }
    .onTapGesture { open?() }
    .pointerStyle(open == nil ? nil : .link)
  }
}

/// How far along something is: a thin amber line on a faint track.
private struct PanelProgress: View {
  let progress: Double

  var body: some View {
    Capsule().fill(Palette.ink.opacity(0.1))
      .overlay(alignment: .leading) {
        GeometryReader { track in
          Capsule().fill(Palette.accent).frame(width: track.size.width * min(max(progress, 0), 1))
        }
      }
      .frame(height: 3)
  }
}

private struct AskButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(.loci("panels.ask")).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(Palette.ink.opacity(0.08), in: .capsule)
        .contentShape(.capsule)
    }
    .buttonStyle(PressStyle(scale: 0.94))
    .changesData()
  }
}

/// A picture before a list line's title, read by its address.
private struct PanelCover: View {
  let url: URL
  @Environment(\.panelPictures) private var pictures
  @Environment(\.host) private var host

  var body: some View {
    Group {
      if let image = pictures?.image(of: url) {
        Image(nsImage: image).resizable().scaledToFill()
      } else {
        Palette.ink.opacity(0.08)
      }
    }
    .frame(width: Size.panelCover, height: Size.panelCover)
    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    .task(id: url) { await pictures?.load(url, from: host) }
  }
}
