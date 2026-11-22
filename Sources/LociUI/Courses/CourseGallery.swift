import LociModel
import SwiftUI

/// A course as its book in the gallery.
struct CourseBook: Identifiable, Hashable {
  let id: EntityID
  let title: String
  let subtitle: String
  /// The share of its lessons read, from 0 to 1.
  var read: Double = 0
  /// While Loci is still building the course: the stage it is at and how far that stage has got.
  var building: Building?

  struct Building: Hashable {
    let stage: CourseStage
    /// `nil` when how far it has got cannot be told.
    let fraction: Double?
    /// Loci is at work on it now, rather than waiting for the person.
    var working = true
  }
}

/// Every course as a cloth-bound book, about four to a row. A book lifts and opens a little under the pointer
/// and springs back when pressed; one being built has amber light running around it, gold leaf catching the
/// light, and its stages under it. A new book falls into place from above.
struct CourseGallery: View {
  let books: [CourseBook]
  /// The book the builder is folded into, which it grows back out of; it is drawn by the builder while open.
  var hidden: EntityID?
  var pointed: EntityID?
  /// The book the builder has just gone back into, which jumps a little as it lands.
  var bumped: Bump?
  let open: (CourseBook) -> Void
  let delete: (CourseBook) -> Void

  var body: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: Size.bookMinimum, maximum: 280), spacing: 30, alignment: .top)],
      alignment: .leading, spacing: 34
    ) {
      ForEach(books) { book in
        GalleryBook(
          book: book, pointed: pointed == book.id, hidden: hidden == book.id,
          bumps: bumped?.book == book.id ? bumped?.serial ?? 0 : 0
        ) {
          open(book)
        }
        .contextMenu {
          Button(role: .destructive) {
            delete(book)
          } label: {
            Text(.loci("course.delete"))
          }
          .changesData()
        }
        .transition(
          .asymmetric(
            insertion: .modifier(active: Falling(progress: 0), identity: Falling(progress: 1)),
            removal: .scale(scale: 0.9).combined(with: .opacity)))
      }
    }
    .animation(Motion.land, value: books.map(\.id))
  }
}

/// A book jumping as the builder goes back into it; a new serial jumps it again.
struct Bump: Equatable {
  let book: EntityID
  let serial: Int
}

/// A book falling into the gallery: from above, turned a little, coming into view as it lands.
struct Falling: ViewModifier, Animatable {
  var progress: Double

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    content
      .offset(y: -60 * (1 - progress))
      .rotationEffect(.degrees(-4 * (1 - progress)))
      .opacity(min(progress * 1.6, 1))
  }
}

/// One book with its name under it, and its stages while it is being built.
struct GalleryBook: View {
  @Environment(\.reducesMotion) private var reduceMotion
  let book: CourseBook
  let pointed: Bool
  let hidden: Bool
  var bumps = 0
  let open: () -> Void
  @State private var hovering = false

  var body: some View {
    let lifted = (hovering || pointed) && !reduceMotion
    Button(action: open) {
      VStack(alignment: .leading, spacing: 0) {
        cover
          .rotation3DEffect(.degrees(lifted ? -9 : 0), axis: (0, 1, 0), anchor: .leading, perspective: 0.6)
          .offset(y: lifted ? -6 : 0)
          .shadow(color: Palette.warmShadow.opacity(lifted ? 0.5 : 0.38), radius: lifted ? 20 : 14, y: lifted ? 22 : 14)
          .shadow(color: Palette.warmShadow.opacity(0.2), radius: 2, y: 2)
          .animation(Motion.tilt, value: lifted)
        Text(book.title)
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundStyle(Palette.ink.opacity(0.9))
          .lineLimit(1)
          .padding(.top, Spacing.s)
        if let building = book.building {
          CourseStageRuler(stage: building.stage, fraction: building.fraction, scale: .book)
            .padding(.top, 10)
            .transition(.opacity)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(BookPress())
    .onHover { hovering = $0 }
    .opacity(hidden ? 0 : 1)
  }

  private var cover: some View {
    ClothBook(title: book.title, subtitle: book.subtitle, read: book.read)
      .overlay {
        if book.building?.working == true {
          FoilSweep().clipShape(ClothBook.shape)
        }
      }
      .amberGlow(book.building?.working == true, corner: Radius.bookSpine + 3, width: 1.5)
      .anchorPreference(key: GrowthOrigins.self, value: .bounds) { [.book(book.id): $0] }
      .keyframeAnimator(initialValue: 1.0, trigger: bumps) { cover, scale in
        cover.scaleEffect(scale)
      } keyframes: { _ in
        CubicKeyframe(1.06, duration: 0.5)
        CubicKeyframe(1, duration: 0.26)
      }
  }
}

/// Pressing a book pushes it in a little; it springs back on release.
private struct BookPress: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.spring(duration: 0.3, bounce: 0.4), value: configuration.isPressed)
  }
}

/// No courses yet: an empty book drawn in pencil under the field, waiting for its first title.
struct EmptyShelf: View {
  var body: some View {
    VStack(spacing: Spacing.l) {
      ZStack {
        ClothBook.shape
          .strokeBorder(Palette.inkFaint.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
        Rectangle().fill(Palette.inkFaint.opacity(0.35)).frame(width: 1).frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, 14).padding(.vertical, 10)
        WishStar().foregroundStyle(Palette.accent.opacity(0.75)).frame(width: 30, height: 30)
      }
      .frame(width: 150, height: 200)
      .rotationEffect(.degrees(-2))
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 70)
    .accessibilityHidden(true)
  }
}
