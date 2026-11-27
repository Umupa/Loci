import LociModel
import SwiftUI

/// The deck on a folded lane: a mark with how many cards wait, opening them over the page. It is there whenever
/// there are cards, with panels on the lane or none.
struct RailDeck: View {
  let side: TalkLayout.Side
  @Environment(\.nextUpDeck) private var deck
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var open = false
  @State private var pointed = false

  var body: some View {
    if let deck, !deck.cards.isEmpty {
      Button {
        open = true
      } label: {
        Image(systemName: "rectangle.stack")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Palette.ink)
          .frame(width: Size.railMark, height: Size.railMark)
          .background(Circle().fill(Palette.fill))
          .overlay(alignment: .topTrailing) {
            Text(verbatim: "\(deck.cards.count)")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(Palette.onAccent)
              .frame(minWidth: 15, minHeight: 15)
              .background(Capsule(style: .circular).fill(Palette.accent))
              .offset(x: 4, y: -4)
          }
          .scaleEffect(pointed ? 1.12 : 1)
          .animation(reduceMotion ? nil : Motion.quick, value: pointed)
          .contentShape(.circle)
          .onHover { pointed = $0 }
      }
      .buttonStyle(PressStyle(scale: 0.9))
      .help(Text(.loci("deck.cards")))
      .accessibilityLabel(Text(.loci("deck.cards")))
      .onChange(of: deck.focused, initial: true) { if deck.focused != nil { open = true } }
      .popover(isPresented: $open, arrowEdge: side == .leading ? .trailing : .leading) {
        RailDeckSheet(deck: closing(deck))
      }
    }
  }

  /// Starting a card closes the cards first, so it opens its project over a clear page.
  private func closing(_ deck: NextUpDeckState) -> NextUpDeckState {
    let actions = deck.actions
    return NextUpDeckState(
      cards: deck.cards, projects: deck.projects, flying: deck.flying,
      actions: NextUpActions(
        start: { card in
          open = false
          actions.start(card)
        },
        set: actions.set, approve: actions.approve, undo: actions.undo))
  }
}

/// The cards opened from the mark, laid out, as tall as they are once laid out and scrolling beyond the
/// tallest a sheet may be: a card that grows as it lays out, such as an event over two days, is never cut.
struct RailDeckSheet: View {
  let deck: NextUpDeckState
  @State private var height = Size.nextUpCard

  var body: some View {
    ScrollView {
      NextUpDeck(state: deck, spread: true)
        .padding(Spacing.s)
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height
        } action: {
          height = $0
        }
    }
    .scrollIndicators(.never)
    .frame(width: Size.railSheet, height: min(height, Size.railSheetTallest))
  }
}
