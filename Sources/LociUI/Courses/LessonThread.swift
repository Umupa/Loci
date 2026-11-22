import LociModel
import SwiftUI

/// A course's lessons as beads on one thread of ink, without numbers. A lesson planned is an empty bead with a
/// dot of pencil in it; the one being written is amber and pulses, its title crossed by light; a written one
/// is solid ink, rippling once when it is done, with its minutes after it. On the reading page a lesson written
/// is a thin empty ring until it has been read, and solid after; the open one is an amber bead with its title
/// underlined as with a highlighter.
struct LessonThread: View {
  /// Ink on a page of the open book, or on the window's own background.
  enum Ink {
    case page, window

    var color: Color { self == .page ? Palette.leafInk : Palette.ink }
    var ground: Color { self == .page ? Palette.leaf : Palette.canvas }
  }

  let lessons: [Row]
  var ink = Ink.page
  var rowHeight: CGFloat = 30
  var choose: ((Lesson.ID) -> Void)?

  /// A lesson as the thread shows it.
  struct Row: Equatable, Identifiable {
    let id: Lesson.ID
    let title: String
    let mark: Mark
    /// The minutes a written lesson takes, shown in the builder's book.
    var minutes: Int?
    /// The lesson open on the reading page.
    var current = false
  }

  enum Mark: Equatable {
    case planned, writing, written, read
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(lessons) { lesson in
        row(lesson)
          .frame(height: rowHeight)
          .contentShape(Rectangle())
          .onTapGesture { choose?(lesson.id) }
          .transition(.opacity.combined(with: .offset(y: 8)))
      }
    }
    .background(alignment: .leading) {
      Rectangle()
        .fill(ink.color.opacity(ink == .page ? 0.18 : 0.15))
        .frame(width: 1)
        .padding(.vertical, rowHeight / 2 - 4)
        .padding(.leading, Size.bead / 2 - 0.5)
    }
    .animation(Motion.arrive, value: lessons.map(\.id))
  }

  private func row(_ lesson: Row) -> some View {
    HStack(spacing: Spacing.s) {
      Bead(mark: lesson.mark, current: lesson.current, ink: ink)
      title(lesson)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 0)
      if let minutes = lesson.minutes, lesson.mark == .written || lesson.mark == .read {
        Text(.loci("course.minutes \(minutes)"))
          .font(.system(size: 10.5, weight: .medium).monospaced())
          .foregroundStyle(ink.color.opacity(0.4))
          .transition(.opacity)
      }
    }
    .font(.system(size: 13, weight: lesson.current ? .semibold : .regular))
    .animation(.easeOut(duration: 0.4), value: lesson.mark)
  }

  @ViewBuilder private func title(_ lesson: Row) -> some View {
    let words = Text(verbatim: lesson.title)
    switch lesson.mark {
    case .writing:
      ShimmerText(text: words, ink: ink.color)
    case .planned:
      words.foregroundStyle(ink.color.opacity(ink == .page ? 0.38 : 0.32))
        .background(alignment: .bottom) { if lesson.current { Highlighter(color: ink.color.opacity(0.1)) } }
    case .written, .read:
      words.foregroundStyle(ink.color.opacity(lesson.current ? 1 : ink == .page ? 0.9 : 0.75))
        .background(alignment: .bottom) { if lesson.current { Highlighter(color: Palette.accent.opacity(0.28)) } }
    }
  }
}

/// The band a highlighter leaves under the lower part of a line.
private struct Highlighter: View {
  let color: Color

  var body: some View {
    Rectangle().fill(color).frame(height: 6).offset(y: -1)
  }
}

/// One bead on the thread.
private struct Bead: View {
  let mark: LessonThread.Mark
  let current: Bool
  let ink: LessonThread.Ink
  @Environment(\.standIns) private var standIns
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var rippled = 0

  var body: some View {
    Group {
      if current, mark != .planned, mark != .writing {
        Circle().fill(Palette.accent)
          .background { Circle().fill(Palette.accent.opacity(0.18)).padding(-4) }
      } else {
        switch mark {
        case .planned:
          Circle().fill(ink.ground)
            .overlay { Circle().strokeBorder(ink.color.opacity(0.22), lineWidth: 1) }
            .overlay { Circle().fill(ink.color.opacity(0.25)).frame(width: 2, height: 2) }
        case .writing:
          PulsingBead(filled: ink == .page)
        case .written where ink == .window:
          Circle().strokeBorder(ink.color.opacity(0.6), lineWidth: 1)
        case .written, .read:
          Circle().fill(ink.color.opacity(ink == .page ? 1 : 0.75))
            .keyframeAnimator(initialValue: Ripple(), trigger: rippled) { bead, ripple in
              bead.overlay {
                Circle().strokeBorder(ink.color.opacity(0.5 * ripple.opacity), lineWidth: 1.5)
                  .padding(-6).scaleEffect(ripple.scale)
              }
            } keyframes: { _ in
              KeyframeTrack(\.scale) { CubicKeyframe(1.4, duration: 0.7) }
              KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: 0.01)
                CubicKeyframe(0, duration: 0.69)
              }
            }
            .onAppear { if mark == .written, standIns == nil, !reduceMotion { rippled += 1 } }
        }
      }
    }
    .frame(width: Size.bead, height: Size.bead)
  }
}

/// A ring spreading out from a bead just inked.
private struct Ripple {
  var scale = 0.4
  var opacity = 0.0
}
