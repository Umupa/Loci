import SwiftUI

/// Items Loci brings into the conversation, as a row of small cards with their covers.
struct ItemCardRow<Card: View>: View {
  var indent = TalkScale.main.indent
  @ViewBuilder let cards: () -> Card

  var body: some View {
    HStack(alignment: .top, spacing: 10) { cards() }
      .padding(.leading, indent)
      .padding(.top, 6)
      .padding(.bottom, Spacing.xxs)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// One item on a card: its cover with how long it runs and whether to watch it first, its title and source.
struct ItemCard<Cover: View>: View {
  let title: String
  let source: String?
  var duration: Text?
  /// The one to start with.
  var first = false
  var width: CGFloat = 170
  var coverHeight: CGFloat = 92
  @ViewBuilder let cover: () -> Cover
  @State private var hovering = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      cover()
        .frame(width: width, height: coverHeight)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
          if let duration {
            duration
              .font(.system(size: 10.5).monospaced())
              .foregroundStyle(Palette.onCover)
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(Palette.coverShade.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
              .padding(Spacing.xs)
          }
        }
        .overlay(alignment: .topLeading) {
          if first {
            Text(.loci("talk.watchFirst"))
              .font(.system(size: 10.5, weight: .semibold))
              .foregroundStyle(Palette.firstInk)
              .padding(.horizontal, 7)
              .padding(.vertical, 1)
              .background(Palette.onCover, in: Capsule())
              .padding(Spacing.xs)
          }
        }
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: title).font(.system(size: 12.5)).foregroundStyle(Palette.ink).lineSpacing(1.5)
        if let source {
          Text(verbatim: source).font(.system(size: 10.5).monospaced()).foregroundStyle(Palette.inkFaint)
        }
      }
      .padding(.top, Spacing.xs)
      .padding(.horizontal, 10)
      .padding(.bottom, 10)
    }
    .frame(width: width, alignment: .leading)
    .background(Palette.surface)
    .clipShape(shape)
    .cardShadow(shape)
    .offset(y: hovering ? -2 : 0)
    .animatingArrivals(hovering)
    .onHover { hovering = $0 }
  }
}
