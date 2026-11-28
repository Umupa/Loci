import LociModel
import SwiftUI

/// What the deck at the top of the panel column shows and asks of the page around it.
struct NextUpDeckState {
  let cards: [NextUp]
  /// The projects the cards belong to, for their seals.
  let projects: [Project.ID: Project]
  /// The card flying into its seal, hidden in the deck meanwhile.
  var flying: EntityID?
  var focused: EntityID? = nil
  let actions: NextUpActions
}

struct NextUpActions {
  let start: (NextUp) -> Void
  let set: (NextUp, SetNextUp.Choice) -> Void
  let approve: (NextUp, ApproveNextUp.Step) -> Void
  /// Removes what the card's approval made.
  let undo: (NextUp, Approved) -> Void
}

extension EnvironmentValues {
  /// Set by the companion's page; without it the panel column has no deck.
  @Entry var nextUpDeck: NextUpDeckState?
}

/// The next-up cards: the first on top, two more tucked under it, all of them laid out under the pointer.
struct NextUpDeck: View {
  let state: NextUpDeckState
  /// Laid out, for a snapshot.
  var spread = false
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var pointed = false
  /// Each card's own height, as it last laid out.
  @State private var heights: [EntityID: CGFloat] = [:]

  private static let tucked: [(offset: CGFloat, scale: CGFloat)] = [(0, 1), (9, 0.95), (17, 0.9)]

  var body: some View {
    let cards = state.cards
    let open = (pointed || spread) && cards.count > 1
    let shown = open ? cards : Array(cards.prefix(Self.tucked.count))
    let top = shown.first.map { height(of: $0) } ?? 0
    ZStack(alignment: .top) {
      ForEach(Array(shown.enumerated()), id: \.element.id) { index, card in
        let place = Self.tucked[min(index, Self.tucked.count - 1)]
        let covered = !open && index > 0
        Group {
          if covered {
            NextUpFace { Color.clear.frame(height: top) }
          } else {
            face(of: card)
              .fixedSize(horizontal: false, vertical: true)
              .onGeometryChange(for: CGFloat.self) {
                $0.size.height
              } action: {
                heights[card.id] = $0
              }
          }
        }
        .scaleEffect(open ? 1 : place.scale, anchor: .top)
        .offset(y: open ? offset(of: index, in: shown) : place.offset)
        .zIndex(Double(cards.count - index))
        .opacity(card.id == state.flying ? 0 : 1)
        .transition(leaving)
      }
    }
    .frame(height: height(of: shown, open: open), alignment: .top)
    .overlay(alignment: .bottomTrailing) {
      if !open, cards.count > 1 {
        HStack(spacing: 4) {
          ForEach(0..<min(cards.count, 5), id: \.self) { index in
            Circle().fill(index == 0 ? Palette.ink : Palette.inkFaint).frame(width: 5, height: 5)
          }
        }
        .offset(x: -18, y: 9)
      }
    }
    .padding(.bottom, cards.isEmpty ? 0 : Spacing.xs)
    .onHover { pointed = $0 }
    .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.86), value: open)
    .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.86), value: cards.map(\.id))
  }

  @ViewBuilder private func face(of card: NextUp) -> some View {
    let project = card.home.project.flatMap { state.projects[$0] }
    switch card.kind {
    case .ask(let question):
      NextUpCard(card: card, question: question, project: project, actions: state.actions)
    case .approval(let approval):
      ApprovalCard(card: card, approval: approval, project: project, actions: state.actions)
    }
  }

  private func height(of card: NextUp) -> CGFloat {
    heights[card.id] ?? Size.nextUpCard
  }

  /// How far down a laid-out card starts: the cards above it and the gaps between.
  private func offset(of index: Int, in cards: [NextUp]) -> CGFloat {
    cards.prefix(index).reduce(0) { $0 + height(of: $1) + Spacing.s }
  }

  private func height(of cards: [NextUp], open: Bool) -> CGFloat {
    guard let first = cards.first else { return 0 }
    if open { return offset(of: cards.count - 1, in: cards) + height(of: cards[cards.count - 1]) }
    let top = height(of: first)
    return Self.tucked.prefix(cards.count).map { $0.offset + $0.scale * top }.max() ?? top
  }

  /// A card the person dealt with slides away; with motion reduced it is simply gone.
  private var leaving: AnyTransition {
    reduceMotion
      ? .identity
      : .asymmetric(
        insertion: .opacity.combined(with: .offset(y: -Spacing.m)),
        removal: .opacity.combined(with: .offset(x: -80)).combined(with: .scale(scale: 0.92)))
  }
}

/// The card's face: the paper, its hairline and its shadow.
struct NextUpFace<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.nextUpCard, style: .continuous)
    content
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background(shape.fill(Palette.surface))
      .overlay(shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
      .shadow(color: Palette.liftShadow.opacity(0.5), radius: 14, y: 10)
  }
}

/// Where a card comes from: the project's seal and name, or the companion and 「聊天」.
struct NextUpSource: View {
  let project: Project?

  var body: some View {
    HStack(spacing: 6) {
      if let project {
        ProjectSeal(symbol: project.symbol, size: 16, locked: !project.remembered)
        project.title
      } else {
        LociAvatar(size: 16)
        Text(.loci("projects.chat"))
      }
    }
    .font(.system(size: 12))
    .foregroundStyle(Palette.inkMuted)
    .lineLimit(1)
  }
}
