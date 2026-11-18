import AppKit
import LociModel
import SwiftUI
import Textual

/// The files under the mentor's `memory/`, newest first, each opened to its text as written.
struct MemoryList: View {
  let files: [MemoryFile]

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(files.enumerated()), id: \.element.name) { index, file in
        MemoryRow(file: file, startsOpen: index == 0)
        Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline)
      }
    }
  }
}

private struct MemoryRow: View {
  let file: MemoryFile
  @State private var open: Bool

  init(file: MemoryFile, startsOpen: Bool) {
    self.file = file
    _open = State(initialValue: startsOpen)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(Motion.fold) { open.toggle() }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "doc.text")
            .font(.system(size: 17, weight: .light))
            .foregroundStyle(Palette.inkFaint)
            .frame(width: 22)
          Text(verbatim: file.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Palette.ink)
          Spacer(minLength: Spacing.s)
          Text(file.modifiedAt.date, format: .relative(presentation: .named))
            .font(.system(size: 11.5))
            .monospacedDigit()
            .foregroundStyle(Palette.inkFaint)
          Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Palette.inkFaint)
            .rotationEffect(.degrees(open ? 90 : 0))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if open {
        StructuredText(markdown: file.text, syntaxExtensions: [.math])
          .font(.system(size: 14))
          .foregroundStyle(Palette.ink)
          .textual.headingStyle(NoteHeading())
          .textual.structuredTextStyle(.default)
          .textual.textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, 36)
          .padding(.trailing, 4)
          .padding(.bottom, 18)
      }
    }
  }
}

/// `SOUL.md` as one page of a manuscript, with a pencil that opens the file in the Mac's editor when the
/// mentor lives on this Mac.
struct SoulSheet: View {
  let soul: String?
  let file: LocalFile?
  let color: MentorColor

  var body: some View {
    ZStack(alignment: .topTrailing) {
      StructuredText(markdown: soul ?? "")
        .font(.system(size: 15, design: .serif))
        .foregroundStyle(Palette.ink)
        .lineSpacing(5)
        .textual.headingStyle(SoulHeading())
        .textual.structuredTextStyle(.default)
        .textual.textSelection(.enabled)
        .padding(.top, 44)
        .padding(.horizontal, 56)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let file {
        Button {
          NSWorkspace.shared.open(file.url)
        } label: {
          Image(systemName: "pencil").font(.system(size: 15)).foregroundStyle(Palette.inkMuted).frame(
            width: 28, height: 28)
        }
        .buttonStyle(PressStyle())
        .help(Text(.loci("mentor.editSoul")))
        .accessibilityLabel(Text(.loci("mentor.editSoul")))
        .padding(14)
        .disabled(soul == nil)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 6).fill(Palette.surface).shadow(color: .black.opacity(0.08), radius: 20, y: 14)
    )
    .overlay(alignment: .top) {
      UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
        .fill(
          LinearGradient(
            colors: [color.color, color.mixed(toward: 0.6, 0.5)], startPoint: .leading, endPoint: .trailing)
        )
        .frame(height: 4)
        .opacity(0.9)
    }
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: Size.hairline))
  }
}

/// The headings of a soul are small labels, so the page reads as a manuscript and not a document.
private struct SoulHeading: StructuredText.HeadingStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .textual.fontScale(13 / 15)
      .fontDesign(.default)
      .fontWeight(.semibold)
      .foregroundStyle(Palette.inkMuted)
      .textual.blockSpacing(.fontScaled(top: 1.6, bottom: 0.4))
  }
}

/// The headings of a memory file stay at the size of its text, so the file reads as notes and not an
/// article: the first level is the text in bold, the levels under it smaller and muted.
private struct NoteHeading: StructuredText.HeadingStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .textual.fontScale(configuration.headingLevel <= 1 ? 1 : 13 / 14)
      .fontWeight(configuration.headingLevel <= 1 ? .bold : .semibold)
      .foregroundStyle(configuration.headingLevel <= 2 ? Palette.ink : Palette.inkMuted)
      .textual.blockSpacing(.fontScaled(top: 1, bottom: 0.3))
  }
}
