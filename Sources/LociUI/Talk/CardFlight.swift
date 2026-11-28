import LociModel
import SwiftUI

/// Where the cards of the deck and the seals of the project bar are, for a started card to fly between them.
struct NextUpAnchors: PreferenceKey {
  struct Value {
    var cards: [EntityID: Anchor<CGRect>] = [:]
    var seals: [Home: Anchor<CGRect>] = [:]
    /// The blank seal of a new project not yet in the bar.
    var newSeal: Anchor<CGRect>?
  }

  static let defaultValue = Value()

  static func reduce(value: inout Value, nextValue: () -> Value) {
    let next = nextValue()
    value.cards.merge(next.cards) { _, new in new }
    value.seals.merge(next.seals) { _, new in new }
    value.newSeal = next.newSeal ?? value.newSeal
  }
}

/// A started card on its way: it rises, shrinks and falls into its seal, then is gone.
struct CardFlight: View {
  let card: NextUp
  let project: Project?
  let from: CGRect
  let to: CGRect
  let landed: () -> Void
  @State private var stage = Stage.deck

  enum Stage { case deck, rising, seal }

  var body: some View {
    NextUpFace {
      VStack(alignment: .leading, spacing: 4) {
        NextUpSource(project: project)
        Text(verbatim: card.what).font(.system(size: 14)).foregroundStyle(Palette.ink).lineLimit(2)
      }
      .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 14))
    }
    .frame(width: from.width, height: from.height)
    .scaleEffect(scale)
    .opacity(stage == .seal ? 0 : 1)
    .position(place)
    .allowsHitTesting(false)
    .onAppear(perform: fly)
  }

  private var scale: CGFloat {
    switch stage {
    case .deck: 1
    case .rising: 0.55
    case .seal: 0.12
    }
  }

  private var place: CGPoint {
    let start = CGPoint(x: from.midX, y: from.midY)
    let end = CGPoint(x: to.midX, y: to.midY)
    switch stage {
    case .deck: return start
    case .rising: return CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 60)
    case .seal: return end
    }
  }

  private func fly() {
    withAnimation(.timingCurve(0.5, 0, 0.3, 1, duration: 0.36)) {
      stage = .rising
    } completion: {
      withAnimation(.timingCurve(0.5, 0, 0.3, 1, duration: 0.36)) {
        stage = .seal
      } completion: {
        landed()
      }
    }
  }
}

extension View {
  /// Tells the companion's page where the seal of `home` is.
  func sealAnchor(_ home: Home?) -> some View {
    anchorPreference(key: NextUpAnchors.self, value: .bounds) { anchor in
      NextUpAnchors.Value(seals: home.map { [$0: anchor] } ?? [:])
    }
  }
}

/// A new project's large seal on its way into the bar: it shrinks along an arc into the blank seal waiting
/// there, then is gone.
struct SealFlight: View {
  let symbol: String?
  let from: CGRect
  let to: CGRect
  let landed: () -> Void
  @State private var progress = 0.0

  var body: some View {
    HeroSeal(symbol: symbol)
      .modifier(Arc(progress: progress, from: from, to: to))
      .allowsHitTesting(false)
      .onAppear {
        withAnimation(Motion.sealFlight) {
          progress = 1
        } completion: {
          landed()
        }
      }
  }

  /// Along a curve that bows up and out, shrinking from the large seal to the bar's.
  private struct Arc: ViewModifier, Animatable {
    var progress: Double
    let from: CGRect
    let to: CGRect

    nonisolated var animatableData: Double {
      get { progress }
      set { progress = newValue }
    }

    func body(content: Content) -> some View {
      let start = CGPoint(x: from.midX, y: from.midY)
      let end = CGPoint(x: to.midX, y: to.midY)
      let bend = CGPoint(x: start.x + (end.x - start.x) * 0.2, y: min(start.y, end.y) - 40)
      let t = progress
      let point = CGPoint(
        x: (1 - t) * (1 - t) * start.x + 2 * (1 - t) * t * bend.x + t * t * end.x,
        y: (1 - t) * (1 - t) * start.y + 2 * (1 - t) * t * bend.y + t * t * end.y)
      let scale = 1 + (to.width / max(from.width, 1) - 1) * t
      content
        .scaleEffect(scale)
        .opacity(t > 0.96 ? 0 : 1)
        .position(point)
    }
  }
}
