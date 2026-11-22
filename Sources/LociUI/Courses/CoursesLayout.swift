import LociModel
import SwiftUI

/// What the builder grows out of and goes back into: the field it was asked for in, or its course's book.
enum GrowthOrigin: Hashable {
  case wish
  case book(EntityID)
}

/// Where the field and each book are laid out.
struct GrowthOrigins: PreferenceKey {
  static let defaultValue: [GrowthOrigin: Anchor<CGRect>] = [:]

  static func reduce(value: inout [GrowthOrigin: Anchor<CGRect>], nextValue: () -> [GrowthOrigin: Anchor<CGRect>]) {
    value.merge(nextValue()) { $1 }
  }
}

/// The courses page: the shelf, and over it, while a course is being built, the builder on a warm veil that
/// blurs the shelf. The builder grows out of the field it was asked for in, goes back into its book when put
/// away, and grows out of the book again when the book is chosen.
struct CoursesLayout<Builder: View>: View {
  let books: [CourseBook]
  /// The course whose builder is open.
  let building: EntityID?
  @ViewBuilder let builder: (EntityID) -> Builder
  /// Where the builder last grew from, and goes back to.
  let origin: GrowthOrigin
  var bumped: Bump?
  var pointed: EntityID?
  /// The builder caught part way through growing, for a snapshot.
  var growth: Double?
  @Binding var wish: String
  let start: (String) -> Void
  let open: (CourseBook) -> Void
  let delete: (CourseBook) -> Void
  @State private var origins: [GrowthOrigin: CGRect] = [:]
  @State private var presence = BuilderPresence()
  @Environment(\.standIns) private var standIns
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    let from = reduceMotion ? .zero : origins[origin] ?? .zero
    let grown = growth ?? presence.grown
    ZStack {
      CourseShelf(
        books: books, wish: $wish, hidden: nil, pointed: pointed, bumped: bumped, start: start, open: open,
        delete: delete
      )
      .blur(radius: 2 * grown)
      if presence.drawn != nil {
        Rectangle().fill(Palette.scrim)
          .background(.ultraThinMaterial.opacity(0.6))
          .ignoresSafeArea()
          .opacity(grown)
      }
      if let drawn = presence.drawn {
        builder(drawn)
          .id(drawn)
          .modifier(Growing(progress: grown, from: from))
          .padding(Spacing.l)
          .allowsHitTesting(building == drawn)
          .transition(.identity)
          .onAppear { grow() }
      }
    }
    .coordinateSpace(.named(CoursesSpace.name))
    .backgroundPreferenceValue(GrowthOrigins.self) { anchors in
      GeometryReader { proxy in
        let frames = anchors.mapValues { proxy[$0] }
        Color.clear.onChange(of: frames, initial: true) { _, now in origins = now }
      }
    }
    .onChange(of: building, initial: true) { _, now in
      switch presence.follow(now) {
      case .growOut: grow()
      case .goBackIn(let course):
        withAnimation(Motion.expand) {
          presence.grown = 0
        } completion: {
          presence.settle(course)
        }
      case .drawAnew, .stay: break
      }
    }
  }

  /// Grows the builder drawn out to its place, at once for a snapshot.
  private func grow() {
    if standIns != nil {
      presence.grown = 1
    } else {
      withAnimation(Motion.expand) { presence.grown = 1 }
    }
  }
}

/// The builder on the courses page: whose builder is drawn, and how far it has grown out of where it came
/// from. It stays drawn all the way back into its book, and only then is gone.
struct BuilderPresence: Equatable {
  /// The course whose builder is drawn: the one open, or the one going back into its book.
  private(set) var drawn: EntityID?
  /// How far the builder drawn has grown out, from 0 to 1; the page animates it.
  var grown = 0.0

  /// What the page does as the builder open changes.
  enum Step: Equatable {
    /// Grow the builder drawn out to its place.
    case growOut
    /// A new builder is drawn, folded up; it grows out once it appears.
    case drawAnew
    /// Shrink the builder of this course back in, then settle.
    case goBackIn(EntityID)
    /// Nothing changes.
    case stay
  }

  /// Follows the builder open changing to `building`.
  mutating func follow(_ building: EntityID?) -> Step {
    switch building {
    case let building? where building == drawn: return .growOut
    case let building?:
      drawn = building
      grown = 0
      return .drawAnew
    case nil: return drawn.map { .goBackIn($0) } ?? .stay
    }
  }

  /// The builder of `course` has finished going back in: it is no longer drawn, unless it was opened again or
  /// another took its place on the way.
  mutating func settle(_ course: EntityID) {
    if drawn == course, grown == 0 { drawn = nil }
  }
}

/// The courses page's own coordinate space, in which the builder grows.
enum CoursesSpace {
  static let name = "courses"
}

/// The builder grown from `from` to its own place: at 0 it is laid over `from`, squeezed to its size and
/// faint; at 1 it is itself.
struct Growing: ViewModifier, Animatable {
  var progress: Double
  let from: CGRect

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let progress = progress
    let from = from
    content
      .visualEffect { effect, proxy in
        let to = proxy.frame(in: .named(CoursesSpace.name))
        let shown = Growing.frame(at: progress, from: from, to: to)
        return
          effect
          .scaleEffect(
            x: to.width > 0 ? shown.width / to.width : 1, y: to.height > 0 ? shown.height / to.height : 1,
            anchor: .topLeading
          )
          .offset(x: shown.minX - to.minX, y: shown.minY - to.minY)
      }
      .opacity(0.25 + 0.75 * min(progress * 1.3, 1))
  }

  /// Where the builder laid out at `to` is drawn at `progress`: over `from` at 0, at `to` at 1, and in
  /// proportion between; at `to` throughout when either has no size.
  nonisolated static func frame(at progress: Double, from: CGRect, to: CGRect) -> CGRect {
    guard from.width > 0, to.width > 0 else { return to }
    let rest = 1 - progress
    return CGRect(
      x: to.minX + rest * (from.minX - to.minX), y: to.minY + rest * (from.minY - to.minY),
      width: to.width + rest * (from.width - to.width), height: to.height + rest * (from.height - to.height))
  }
}
