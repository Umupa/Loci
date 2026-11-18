import LociModel
import SwiftUI
import Textual

/// What Loci wrote each night: the days down one side, the chosen day's entry in serif beside them.
struct DiaryTab: View {
  let diaries: [Diary.Heading]
  @State private var chosen: Day?

  var body: some View {
    HStack(alignment: .top, spacing: 40) {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(diaries, id: \.day) { heading in
          DayButton(day: heading.day, chosen: heading.day == shown) { chosen = heading.day }
        }
      }
      .frame(width: 120, alignment: .leading)
      if let shown { DiaryEntry(day: shown).id(shown) }
    }
  }

  /// The day chosen, or the newest.
  private var shown: Day? {
    chosen ?? diaries.first?.day
  }
}

private struct DayButton: View {
  let day: Day
  let chosen: Bool
  let choose: () -> Void

  var body: some View {
    Button(action: choose) {
      Text(verbatim: day.short)
        .font(.system(size: 12).monospaced())
        .foregroundStyle(chosen ? Palette.accentInk : Palette.inkMuted)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(chosen ? Palette.tint : .clear, in: RoundedRectangle(cornerRadius: Radius.row))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(chosen ? .isSelected : [])
  }
}

/// One night's entry: its title, when it was written, what Loci thought, and what it means to remember.
private struct DiaryEntry: View {
  let day: Day
  @State private var diary: Feed<Diary>?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let diary = diary?.value {
        if let title = diary.heading.title {
          Text(serif: title, Serif.Face(size: 22, weight: .semibold)).padding(.bottom, 4)
        }
        Text(verbatim: when(diary.heading))
          .font(.system(size: 11.5).monospaced())
          .foregroundStyle(Palette.inkFaint)
          .padding(.bottom, 18)
        StructuredText(diary.body, parser: SerifMarkdown(face: Serif.Face(size: 16.5)))
          .lineSpacing(16.5 * 0.85 - 4)
          .textual.headingStyle(SmallHeading())
          .textual.structuredTextStyle(.default)
          .textual.textSelection(.enabled)
        if !diary.toRemember.isEmpty {
          PageLabel(title: Text(.loci("loci.toRemember"))).padding(.top, Spacing.l).padding(.bottom, Spacing.xs)
          VStack(alignment: .leading, spacing: 6) {
            ForEach(diary.toRemember, id: \.self) { line in
              HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(verbatim: "•").font(.system(size: 15, design: .serif))
                Text(serif: line, Serif.Face(size: 15))
              }
            }
          }
          .padding(.leading, 6)
        }
      }
    }
    .foregroundStyle(Palette.ink)
    .frame(maxWidth: 600, alignment: .leading)
    .subscribing(OneDiary(day: day), into: $diary)
  }

  private func when(_ heading: Diary.Heading) -> String {
    [heading.day.description, heading.writtenAt?.description].compactMap { $0 }.joined(separator: " · ")
  }
}
