import SwiftUI

/// How large a conversation is drawn: the main conversation, or the narrower one beside something read.
enum TalkScale {
  case main, companion

  var face: CGFloat { self == .main ? 30 : 26 }
  var fontSize: CGFloat { self == .main ? 14.5 : 14 }
  /// The widest a bubble gets, as a share of the column.
  var widest: CGFloat { self == .main ? 0.74 : 0.86 }
  /// Where things under a bubble start: past the face and the gap beside it.
  var indent: CGFloat { face + Spacing.xs + 2 }
}

/// One message as a bubble: Loci's on the left with its face beside the last of a run, the person's on the
/// right in amber.
struct BubbleRow<Words: View, Beside: View>: View {
  let speaker: Speaker
  let position: BubblePosition
  /// Whether it answers the other speaker, which leaves more room above it.
  let turn: Bool
  let scale: TalkScale
  let words: Words
  /// Next to the bubble, on the side away from the edge, such as copying the answer.
  let beside: Beside

  init(
    speaker: Speaker, position: BubblePosition, turn: Bool, scale: TalkScale = .main,
    @ViewBuilder words: () -> Words, @ViewBuilder beside: () -> Beside
  ) {
    self.speaker = speaker
    self.position = position
    self.turn = turn
    self.scale = scale
    self.words = words()
    self.beside = beside()
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: Spacing.xs + 2) {
      if speaker == .loci {
        LociAvatar(size: scale.face)
          .opacity(position.showsFace ? 1 : 0)
          .animation(nil, value: position.showsFace)
      }
      CappedWidth(share: scale.widest, aside: speaker == .loci ? scale.indent : 0) { bubble }
      beside
    }
    .frame(maxWidth: .infinity, alignment: speaker == .loci ? .leading : .trailing)
    .padding(.top, turn ? 14 : 3)
  }

  @ViewBuilder private var bubble: some View {
    let shape = Self.shape(speaker, position)
    let filled =
      words
      .font(.system(size: scale.fontSize))
      .lineSpacing(scale.fontSize * 0.3)
      .foregroundStyle(Palette.ink)
      .padding(.vertical, Spacing.xs)
      .padding(.horizontal, 13)
    if speaker == .loci {
      filled.background(Palette.surface, in: shape).cardShadow(shape)
    } else {
      filled.background(Palette.tint, in: shape)
    }
  }

  /// The corners: round, except tighter where a bubble meets the next from the same speaker and where
  /// the person's last points at them.
  static func shape(_ speaker: Speaker, _ position: BubblePosition) -> UnevenRoundedRectangle {
    let round = Radius.message
    let join = Radius.messageJoin
    if speaker == .person {
      return UnevenRoundedRectangle(
        topLeadingRadius: round, bottomLeadingRadius: round, bottomTrailingRadius: join, topTrailingRadius: round,
        style: .continuous)
    }
    let top: CGFloat = position == .first || position == .alone ? round : join
    let bottom: CGFloat = position == .last ? round : join
    return UnevenRoundedRectangle(
      topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: round, topTrailingRadius: round,
      style: .continuous)
  }
}

extension BubbleRow where Beside == EmptyView {
  init(
    speaker: Speaker, position: BubblePosition, turn: Bool, scale: TalkScale = .main,
    @ViewBuilder words: () -> Words
  ) {
    self.init(speaker: speaker, position: position, turn: turn, scale: scale, words: words) { EmptyView() }
  }
}

/// Lays out its content only as wide as it needs, and no wider than a share of the row it sits in: the
/// width offered plus `aside`, what stands beside it in the row.
struct CappedWidth: Layout {
  let share: CGFloat
  var aside: CGFloat = 0

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let only = subviews.first else { return .zero }
    return only.sizeThatFits(capped(proposal))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
  }

  private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
    ProposedViewSize(width: proposal.width.map { ($0 + aside) * share }, height: proposal.height)
  }
}
