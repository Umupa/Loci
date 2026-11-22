import LociModel
import SwiftUI

/// Everything the atlas page draws of a course: the atlas, how far each lesson it points at has got, and the
/// lessons whose part Loci is still adding.
struct AtlasShown: Equatable {
  let atlas: CourseAtlas
  var lessons: [Lesson.ID: AtlasLesson]
  /// Lessons read whose part is not drawn yet, in reading order.
  var adding: [AtlasLesson]

  init(atlas: CourseAtlas, lessons: [AtlasLesson], adding: [Lesson.ID] = []) {
    self.atlas = atlas
    self.lessons = Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    self.adding = lessons.filter { adding.contains($0.id) }
  }

  init?(_ page: CoursePage, writing: Lesson.ID?) {
    guard let atlas = page.atlas else { return nil }
    let adding = page.course.pendingEvents.compactMap { pending -> Lesson.ID? in
      if case .drawAtlas(let lesson?) = pending.event { lesson } else { nil }
    }
    self.init(
      atlas: atlas,
      lessons: page.lessons.map { lesson in
        let mark: LessonThread.Mark =
          lesson.id == writing ? .writing : lesson.body != .written ? .planned : lesson.isRead ? .read : .written
        return AtlasLesson(id: lesson.id, title: lesson.lesson.title, mark: mark)
      }, adding: adding)
  }
}

/// A lesson as the atlas shows it: a bead, and its title under the pointer.
struct AtlasLesson: Equatable, Identifiable {
  let id: Lesson.ID
  let title: String
  let mark: LessonThread.Mark
}

/// Atlas text with its two marks: `**strong**`, and `` `code` `` in monospace on a faint ground.
enum AtlasInline {
  static func text(
    _ line: AtlasText, size: CGFloat, serif: Bool = false, weight: Font.Weight = .regular,
    highlight: Bool = false
  ) -> Text {
    Text(attributed(line.description, size: size, serif: serif, weight: weight, highlight: highlight))
  }

  static func attributed(_ line: String, size: CGFloat, serif: Bool, weight: Font.Weight, highlight: Bool)
    -> AttributedString
  {
    var result = AttributedString()
    for (piece, kind) in pieces(of: line) {
      var part: AttributedString
      switch kind {
      case .code:
        part = AttributedString(piece)
        part.font = .system(size: size * 0.9, design: .monospaced)
        part.backgroundColor = Palette.fillStrong
      case .strong, .plain:
        let strong = kind == .strong
        let face: Font.Weight = strong ? (weight == .regular ? .semibold : .bold) : weight
        if serif {
          part = Serif.attributed(piece, Serif.Face(size: size, weight: face))
        } else {
          part = AttributedString(piece)
          part.font = .system(size: size, weight: face)
        }
        if strong, highlight { part.backgroundColor = Palette.mark }
      }
      result += part
    }
    return result
  }

  enum Kind { case plain, strong, code }

  /// The line cut where its marks begin and end; a mark left open is read as plain text.
  static func pieces(of line: String) -> [(String, Kind)] {
    var pieces: [(String, Kind)] = []
    var rest = Substring(line)
    while !rest.isEmpty {
      if rest.hasPrefix("**"), let end = rest.dropFirst(2).range(of: "**") {
        pieces.append((String(rest[rest.index(rest.startIndex, offsetBy: 2)..<end.lowerBound]), .strong))
        rest = rest[end.upperBound...]
      } else if rest.hasPrefix("`"), let end = rest.dropFirst().firstIndex(of: "`") {
        pieces.append((String(rest[rest.index(after: rest.startIndex)..<end]), .code))
        rest = rest[rest.index(after: end)...]
      } else {
        let next = rest.dropFirst().firstIndex { $0 == "*" || $0 == "`" } ?? rest.endIndex
        let plain = String(rest[..<next])
        if let last = pieces.last, last.1 == .plain {
          pieces[pieces.count - 1].0 += plain
        } else {
          pieces.append((plain, .plain))
        }
        rest = rest[next...]
      }
    }
    return pieces.filter { !$0.0.isEmpty }
  }
}

/// The lessons a part of the atlas comes from, as small beads: solid once read, a ring when written, a pencil
/// ring before. Pointing at one names it; clicking opens it.
struct AtlasBeads: View {
  @Environment(\.atlasLessons) private var lessons
  @Environment(\.openAtlasLesson) private var open
  let ids: [Lesson.ID]

  var body: some View {
    let shown = ids.compactMap { lessons[$0] }
    HStack(spacing: 5) {
      ForEach(shown) { lesson in
        AtlasBead(mark: lesson.mark)
          .contentShape(Rectangle().inset(by: -4))
          .onTapGesture { open(lesson.id) }
          .help(Text(verbatim: lesson.title))
      }
    }
  }
}

/// A lesson's small bead in the atlas, marked as on the thread.
struct AtlasBead: View {
  let mark: LessonThread.Mark
  var size: CGFloat = 8

  var body: some View {
    Group {
      switch mark {
      case .read: Circle().fill(Palette.ink)
      case .written: Circle().strokeBorder(Palette.ink.opacity(0.65), lineWidth: 1.2)
      case .writing: Circle().fill(Palette.accent)
      case .planned: Circle().strokeBorder(Palette.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [1.6, 1.6]))
      }
    }
    .frame(width: size, height: size)
  }
}

extension EnvironmentValues {
  @Entry var atlasLessons: [Lesson.ID: AtlasLesson] = [:]
  @Entry var openAtlasLesson = OpenAtlasLesson { _ in }
}

/// Opens one of the course's lessons from its bead in the atlas.
struct OpenAtlasLesson {
  let action: (Lesson.ID) -> Void

  func callAsFunction(_ lesson: Lesson.ID) {
    action(lesson)
  }
}
