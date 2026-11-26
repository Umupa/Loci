import SwiftUI

/// How large a conversation is drawn: the main conversation, or the narrower one beside something read.
enum TalkScale {
  case main, companion

  var fontSize: CGFloat { self == .main ? 15 : 14 }
  /// The most of the column a bubble takes, and the widest it gets.
  var share: CGFloat { self == .main ? 0.84 : 0.86 }
  var widest: CGFloat { Size.messageWidest }
}

/// One message as a bubble: Loci's on the left, the person's on the right a shade apart.
struct BubbleRow<Words: View, Beside: View>: View {
  let speaker: Speaker
  let scale: TalkScale
  let words: Words
  /// Next to the bubble, on the side away from the edge, such as copying the answer.
  let beside: Beside
  @Environment(\.messageWidest) private var messageWidest

  init(speaker: Speaker, scale: TalkScale = .main, @ViewBuilder words: () -> Words, @ViewBuilder beside: () -> Beside) {
    self.speaker = speaker
    self.scale = scale
    self.words = words()
    self.beside = beside()
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: Spacing.xs) {
      if speaker == .person { beside }
      CappedWidth(share: scale.share, widest: scale == .main ? messageWidest : scale.widest) { bubble }
      if speaker == .loci { beside }
    }
    .frame(maxWidth: .infinity, alignment: speaker == .loci ? .leading : .trailing)
  }

  private var bubble: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.message, style: .circular)
    return
      words
      .font(.system(size: scale.fontSize))
      .lineSpacing(scale.fontSize * 0.3)
      .foregroundStyle(Palette.ink)
      .padding(.vertical, 14.5)
      .padding(.horizontal, 16)
      .background(speaker == .loci ? Palette.bubble : Palette.bubbleMine, in: shape)
      .overlay {
        if speaker == .loci { shape.strokeBorder(Palette.bubbleEdge, lineWidth: Size.hairline) }
      }
  }
}

extension BubbleRow where Beside == EmptyView {
  init(speaker: Speaker, scale: TalkScale = .main, @ViewBuilder words: () -> Words) {
    self.init(speaker: speaker, scale: scale, words: words) { EmptyView() }
  }
}

/// Lays out its content only as wide as it needs, and no wider than a share of the row it sits in, or
/// `widest`.
struct CappedWidth: Layout {
  let share: CGFloat
  var widest: CGFloat = .infinity

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let only = subviews.first else { return .zero }
    return only.sizeThatFits(capped(proposal))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
  }

  /// No width offered, as in a horizontal scroll, is offered the widest it may be when there is one.
  private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
    let width = proposal.width.map { min($0 * share, widest) } ?? (widest.isFinite ? widest : nil)
    return ProposedViewSize(width: width, height: proposal.height)
  }
}
