import LociModel
import SwiftUI

/// What the card of an item Loci put into the library says under its title: where its work stands while it
/// goes on, why it stopped, and once it is done what it is and where it comes from.
enum SavedItemLine {
  static func text(_ item: Item, work: JobLine) -> Text {
    switch work {
    case .working(let activity, let progress?):
      Text(
        joining: Text(activity.name), Text(verbatim: " · "),
        Text(progress.value, format: .percent.precision(.fractionLength(0))).monospacedDigit())
    case .working(let activity, nil):
      Text(activity.name)
    case .action(let fix, let problem):
      (fix.why(problem) ?? Text(.loci("conversation.stopped"))).foregroundStyle(Palette.accentInk)
    case .none:
      SavedItemByline(item).text
    }
  }

  /// How far along the work is, while it goes on.
  static func progress(_ work: JobLine) -> Double? {
    if case .working(_, let progress?) = work { progress.value } else { nil }
  }
}

/// An item Loci put into the library and that has been deleted since, said faintly.
struct DeletedItemLine: View {
  let title: String?

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: Symbols.tool(.delete)).font(.system(size: 10))
      if let title {
        Text(joining: Text(.loci("added.deleted")), Text(verbatim: " · "), Text(verbatim: title).strikethrough())
      } else {
        Text(.loci("added.deleted"))
      }
    }
    .font(.system(size: 11))
    .foregroundStyle(Palette.inkFaint)
    .lineLimit(1)
    .truncationMode(.tail)
    .padding(.leading, Spacing.xxs)
  }
}
