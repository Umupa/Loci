import AppKit
import LociModel
import SwiftUI

/// A mentor's mark: its white sign on a lit sphere in the mentor's colour.
struct Avatar: View {
  let mentor: Mentor
  let size: CGFloat

  var body: some View {
    let tone = mentor.tone
    Circle()
      .fill(
        RadialGradient(
          stops: [
            .init(color: tone.mixed(toward: 1, 0.3), location: 0), .init(color: tone.color, location: 0.55),
            .init(color: tone.mixed(toward: 0, 0.25), location: 1),
          ], center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: size * 0.75)
      )
      .overlay(Circle().strokeBorder(.black.opacity(0.14), lineWidth: Size.hairline))
      .overlay { Sign(art: MarkArt.mentor(mentor.mark), size: size) }
      .frame(width: size, height: size)
      .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
      .accessibilityHidden(true)
  }
}

/// A course's mark: its white sign on a rounded square in the mentor's colour.
struct CourseMark: View {
  let mentor: Mentor
  let size: CGFloat

  var body: some View {
    let tone = mentor.tone
    let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
    shape
      .fill(
        LinearGradient(
          colors: [tone.mixed(toward: 1, 0.16), tone.mixed(toward: 0, 0.16)], startPoint: .top, endPoint: .bottom)
      )
      .overlay(shape.strokeBorder(.black.opacity(0.14), lineWidth: Size.hairline))
      .overlay { Sign(art: MarkArt.course(mentor.courseMark), size: size) }
      .frame(width: size, height: size)
      .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
      .accessibilityHidden(true)
  }
}

/// A white sign drawn at four fifths of its mark, with a faint shadow to lift it off the colour.
private struct Sign: View {
  let art: NSImage?
  let size: CGFloat

  var body: some View {
    if let art {
      Image(nsImage: art)
        .resizable()
        .frame(width: size * 0.8, height: size * 0.8)
        .shadow(color: .black.opacity(0.25), radius: max(0.3, size / 120), y: max(0.3, size / 120))
    }
  }
}

extension Mentor {
  /// The mentor's colour as it is shown: a colour from an earlier version becomes the nearest one of the palette.
  var tone: MentorColor { color.nearestInPalette }
}

/// The drawings shipped with the app, loaded once each.
@MainActor
enum MarkArt {
  private static var loaded: [String: NSImage] = [:]

  static func mentor(_ mark: Mentor.Mark) -> NSImage? { image("mentor-" + mark.rawValue) }
  static func course(_ mark: Mentor.CourseMark) -> NSImage? { image("course-" + mark.rawValue) }
  static func agent(_ provider: Mentor.Provider) -> NSImage? { image("agent-" + provider.rawValue) }

  private static func image(_ name: String) -> NSImage? {
    if let image = loaded[name] { return image }
    guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
      let image = NSImage(contentsOf: url)
    else { return nil }
    loaded[name] = image
    return image
  }
}
