import SwiftUI

/// The course lying open on the desk while it is written: bound in its cloth, the contents on the left page,
/// the lesson being written on the right, a paragraph at a time rising into place however much arrives at once.
/// The pages keep their size: once the lesson outgrows its page, its latest paragraphs stay in view and the
/// earlier ones fade away over the top. When a lesson is done its page turns over, and the pages under the
/// right one grow thicker with each lesson written.
struct OpenBook: View {
  let title: String
  let subtitle: String?
  let lessons: [LessonLine]
  let leaf: Leaf?
  /// A page caught part way through turning, for a snapshot: the lesson on it and how far over it is.
  var turning: (leaf: Leaf, progress: Double)?
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.standIns) private var standIns
  @State private var turned: Leaf?
  @State private var turn = 0.0
  @State private var pace: ParagraphPace?

  var body: some View {
    let written = lessons.filter { if case .written = $0.state { true } else { false } }.count
    HStack(spacing: 0) {
      contents.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.leaf)
        .overlay(alignment: .trailing) { Gutter(toward: .leading).frame(width: 50) }
      ZStack {
        page(leaf, showing: shown)
        if let flipping = turning?.leaf ?? turned {
          TurningPage(progress: turning?.progress ?? turn) { page(flipping, showing: flipping.paragraphs.count) }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .foregroundStyle(Palette.leafInk)
    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    .overlay(alignment: .trailing) { PageEdges(count: min(written, 6) * 2).offset(x: 1) }
    .background { cover }
    .frame(width: Size.openBook.width, height: Size.openBook.height)
    .compositingGroup()
    .shadow(color: Palette.warmShadow.opacity(0.45), radius: 30, y: 28)
    .onChange(of: leaf) { old, new in
      guard let old, old.number != new?.number, !reduceMotion else { return }
      turned = Leaf(number: old.number, title: old.title, paragraphs: old.paragraphs, writing: false)
      turn = 0
      withAnimation(Motion.turn) {
        turn = 1
      } completion: {
        turned = nil
      }
    }
    .onChange(of: leaf?.number, initial: true) { old, new in
      guard let leaf else {
        pace = nil
        return
      }
      let turnedTo = old != nil && old != new && leaf.writing
      pace = ParagraphPace(number: leaf.number, showing: turnedTo ? 0 : leaf.paragraphs.count, at: .now)
      pace?.arrived(leaf.paragraphs.count, at: .now)
    }
    .onChange(of: leaf?.paragraphs.count) { _, total in
      guard let total, pace?.number == leaf?.number else { return }
      pace?.arrived(total, at: .now)
    }
    .task(id: pace?.next) {
      guard let next = pace?.next else { return }
      try? await Task.sleep(until: next, clock: .continuous)
      guard !Task.isCancelled else { return }
      withAnimation(Motion.arrive) { pace?.catchUp(at: .now) }
    }
  }

  /// How many of the open page's paragraphs are in view: all of them in a snapshot, or a page not being paced.
  private var shown: Int {
    guard let leaf else { return 0 }
    guard standIns == nil, let pace, pace.number == leaf.number else { return leaf.paragraphs.count }
    return min(pace.shown, leaf.paragraphs.count)
  }

  private var cover: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(BookDesign(title: title).clothColor)
      .overlay { ClothWeave().clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)) }
      .padding(.horizontal, -10).padding(.top, -8).padding(.bottom, -10)
  }

  private var contents: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(serif: title, Serif.Face(size: 15, weight: .semibold)).padding(.bottom, 4)
      if let subtitle {
        Text(serif: subtitle, Serif.Face(size: 12)).foregroundStyle(Palette.leafInk.opacity(0.5))
      }
      LessonThread(lessons: lessons.map(\.threadRow), ink: .page)
        .padding(.top, 18)
    }
    .lineLimit(1)
    .padding(.top, 32).padding(.leading, 30).padding(.trailing, 26)
  }

  private func page(_ leaf: Leaf?, showing count: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if let leaf {
        InkedText(serif: leaf.title, Typography.leafTitle)
          .id(leaf.title)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        LatestLines(spacing: 10, fade: 46) {
          ForEach(Array(leaf.paragraphs.prefix(count).enumerated()), id: \.offset) { index, paragraph in
            paragraphText(paragraph, last: leaf.writing && index == count - 1)
              .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
          }
          LinearGradient(colors: [Palette.leaf, Palette.leaf.opacity(0)], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
            .fadesOverflow()
        }
        .padding(.top, 10)
        .clipped()
      }
    }
    .padding(.top, 32).padding(.leading, 34).padding(.trailing, 28).padding(.bottom, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .overlay(alignment: .bottom) {
      if let leaf {
        Text(verbatim: "\(leaf.number)")
          .font(.system(size: 10, weight: .medium).monospaced())
          .foregroundStyle(Palette.leafInk.opacity(0.35))
          .padding(.bottom, 16)
      }
    }
    .background(Palette.leaf)
    .overlay(alignment: .leading) { Gutter(toward: .trailing).frame(width: 50) }
  }

  @ViewBuilder private func paragraphText(_ paragraph: String, last: Bool) -> some View {
    let words = Text(serif: paragraph, Typography.leafBody)
    Group {
      if last {
        Blinking { on in
          Text(joining: words, Text(verbatim: "\u{200A}▏").foregroundStyle(Palette.accent.opacity(on ? 1 : 0)))
        }
      } else {
        words
      }
    }
    .foregroundStyle(Palette.leafInk.opacity(0.82))
    .lineSpacing(13.5 * 0.75)
    .fixedSize(horizontal: false, vertical: true)
  }
}

extension LessonLine {
  var threadRow: LessonThread.Row {
    switch state {
    case .planned: LessonThread.Row(id: id, title: title, mark: .planned)
    case .writing: LessonThread.Row(id: id, title: title, mark: .writing)
    case .written(let minutes): LessonThread.Row(id: id, title: title, mark: .written, minutes: minutes)
    }
  }
}

/// The shadow where a page curves down into the spine.
private struct Gutter: View {
  let toward: UnitPoint

  var body: some View {
    LinearGradient(
      stops: [.init(color: .black.opacity(0.15), location: 0), .init(color: .clear, location: 1)],
      startPoint: toward == .leading ? .trailing : .leading, endPoint: toward == .leading ? .leading : .trailing
    )
    .opacity(0.9)
    .allowsHitTesting(false)
  }
}

/// The edges of the pages under the right-hand one, one more pair for each lesson written.
private struct PageEdges: View {
  let count: Int

  var body: some View {
    HStack(spacing: 0) {
      ForEach(0..<count, id: \.self) { index in
        Rectangle().fill(index.isMultiple(of: 2) ? Color.black.opacity(0.18) : Palette.leafShade).frame(width: 1)
      }
    }
    .padding(.vertical, 2)
    .frame(width: CGFloat(count), alignment: .leading)
    .offset(x: CGFloat(count))
    .animation(.easeOut(duration: 0.6), value: count)
  }
}

/// On and off twice a second, for the caret after words still being written; held on for a snapshot and
/// while the person has asked for less motion.
private struct Blinking<Content: View>: View {
  @Environment(\.standIns) private var standIns
  @Environment(\.reducesMotion) private var reduceMotion
  @ViewBuilder let content: (Bool) -> Content

  var body: some View {
    TimelineView(.periodic(from: .distantPast, by: 0.5)) { context in
      let still = standIns != nil || reduceMotion
      content(still || Int(context.date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2))
    }
  }
}

/// A page turning over at the spine: it rises, darkens as it stands edge on, and is gone once past half way,
/// its back never shown.
struct TurningPage<Page: View>: View {
  let progress: Double
  @ViewBuilder let page: () -> Page

  var body: some View {
    let angle = -178 * progress
    page()
      .overlay { Color.black.opacity(0.3 * min(progress / 0.55, 1)) }
      .rotation3DEffect(.degrees(angle), axis: (0, 1, 0), anchor: .leading, perspective: 0.5)
      .opacity(angle > -90 ? 1 : 0)
      .shadow(color: .black.opacity(0.25 * sin(progress * .pi)), radius: 12, x: -8 * sin(progress * .pi))
      .allowsHitTesting(false)
  }
}
