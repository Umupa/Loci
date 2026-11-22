import AppKit
import LociModel
import SwiftUI

/// The lesson open on the reading page.
enum ShownLesson: Equatable {
  /// Written: its title, how long it takes to read, and its Markdown.
  case written(Lesson.ID, title: String, minutes: Int, markdown: String)
  /// Not written yet; `writing` while Loci is writing it.
  case unwritten(Lesson.ID, title: String, writing: Bool)
  /// Written, its text still on its way.
  case arriving
}

/// The lesson after the open one, as the card at the end of the lesson.
struct NextLesson: Equatable {
  let id: Lesson.ID
  let title: String
  let writing: Bool
}

/// What a lesson shows besides its text.
enum LessonFacts {
  /// The number of the source `url` cites, counting the course's sources from 1: the first source whose address
  /// it starts with, ignoring where in it the link points.
  static func citation(of url: URL, in sources: [URL]) -> Int? {
    let cited = bare(url)
    return sources.firstIndex { cited.hasPrefix(bare($0)) }.map { $0 + 1 }
  }

  /// Minutes to read `markdown`: about four hundred Chinese characters or two hundred and twenty English words a
  /// minute, and never less than one.
  static func minutes(_ markdown: String) -> Int {
    var characters = 0
    var words = 0
    var inWord = false
    for scalar in markdown.unicodeScalars {
      if Serif.isCJK(scalar) {
        characters += 1
        inWord = false
      } else if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
        if !inWord { words += 1 }
        inWord = true
      } else {
        inWord = false
      }
    }
    return max(1, Int((Double(characters) / 400 + Double(words) / 220).rounded()))
  }

  /// "Loci · 8 minutes" after Loci's face, under a lesson's title.
  @MainActor static func byline(face: LociFace, minutes: Int) -> NSAttributedString {
    let line = NSMutableAttributedString()
    if let picture = face.image {
      let side: CGFloat = 20
      let round = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
        NSBezierPath(ovalIn: rect).addClip()
        picture.draw(in: rect)
        return true
      }
      let attachment = NSTextAttachment()
      attachment.image = round
      attachment.bounds = CGRect(x: 0, y: -5, width: side, height: side)
      line.append(NSAttributedString(attachment: attachment))
      line.append(NSAttributedString(string: "  "))
    }
    line.append(
      NSAttributedString(
        string: String(localized: .loci("course.byline \(minutes)")),
        attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Tones.inkMuted]))
    return line
  }

  private static func bare(_ url: URL) -> String {
    let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let host = parts?.host?.replacing(/^www\./, with: "") ?? ""
    let path = parts?.path ?? ""
    return host + (path.hasSuffix("/") ? String(path.dropLast()) : path)
  }
}

/// A lesson not written yet: its title faint, pencil lines where the text will be, and a button to have it
/// written now; while Loci writes it, the title shimmers and the button is gone.
struct UnwrittenLesson: View {
  let title: String
  let writing: Bool
  let writeNow: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Group {
        if writing {
          ShimmerText(text: Text(serif: title, Typography.lessonTitle))
        } else {
          Text(serif: title, Typography.lessonTitle).foregroundStyle(Palette.ink.opacity(0.3))
        }
      }
      .padding(.bottom, Spacing.m)
      ForEach(0..<5, id: \.self) { line in
        PencilGuide(ink: Palette.ink.opacity(0.2))
          .padding(.trailing, line.isMultiple(of: 2) ? 0 : Size.lessonColumn * 0.22)
          .padding(.vertical, 15)
      }
      if !writing {
        Button(action: writeNow) {
          Label {
            Text(.loci("course.writeNow"))
          } icon: {
            Image(systemName: Symbols.pencil)
          }
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Palette.onAccent)
          .padding(.horizontal, 20)
          .padding(.vertical, 11)
          .background(Capsule().fill(Palette.accent))
        }
        .buttonStyle(AnswerPress(scale: 0.95))
        .changesData()
        .padding(.top, Spacing.m)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
      }
      Spacer(minLength: 0)
    }
    .animation(Motion.standard, value: writing)
    .frame(maxWidth: Size.lessonColumn, alignment: .leading)
    .padding(.top, 62)
    .padding(.horizontal, Spacing.xl)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The card at the end of a lesson for the one after it; its title shimmers while Loci is still writing it.
struct NextLessonCard: View {
  let next: NextLesson
  let open: () -> Void
  @State private var hovering = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    Button(action: open) {
      HStack(spacing: Spacing.m) {
        if next.writing {
          PulsingBead(filled: false)
        } else {
          Circle().strokeBorder(Palette.inkMuted, lineWidth: 1).frame(width: Size.bead, height: Size.bead)
        }
        Group {
          if next.writing {
            ShimmerText(text: Text(serif: next.title, Serif.Face(size: 19, weight: .semibold)))
          } else {
            Text(serif: next.title, Serif.Face(size: 19, weight: .semibold)).foregroundStyle(Palette.ink)
          }
        }
        .lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: Symbols.next).font(.system(size: 15)).foregroundStyle(Palette.inkMuted)
      }
      .padding(.horizontal, 22)
      .padding(.vertical, 20)
      .background(shape.fill(Palette.surface))
      .overlay { shape.strokeBorder(Palette.cardEdge, lineWidth: Size.hairline) }
      .shadow(color: Palette.warmShadow.opacity(0.16), radius: 18, y: 10)
      .offset(y: hovering ? -2 : 0)
      .contentShape(shape)
    }
    .buttonStyle(AnswerPress())
    .onHover { hovering = $0 }
    .animation(.spring(duration: 0.3, bounce: 0.3), value: hovering)
    .frame(maxWidth: Size.lessonColumn)
    .padding(.horizontal, Spacing.xl)
    .padding(.bottom, Spacing.l)
  }
}
