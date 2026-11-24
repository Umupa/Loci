import LociModel
import SwiftUI

/// What Loci remembers and knows about the person, each line with its day and where it happened, beside
/// what it wrote down today.
struct MemoryTab: View {
  let memory: [Line<MemoryEntry>]
  let profile: [Line<MemoryEntry>]
  let today: DayNotes

  var body: some View {
    HStack(alignment: .top, spacing: 28) {
      VStack(alignment: .leading, spacing: 6) {
        PageLabel(title: Text(.loci("loci.remembered")), file: "MEMORY.md")
        MemoryList(lines: memory, file: .memory).padding(.bottom, 16)
        PageLabel(title: Text(.loci("loci.aboutYou")), file: "USER.md")
        MemoryList(lines: profile, file: nil)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .leading, spacing: 6) {
        PageLabel(title: Text(.loci("loci.today")), file: "notes/\(today.day).md")
        TodayNotes(notes: today.notes)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Lines of a memory file on one card. With `file`, each line under the pointer offers to be forgotten.
private struct MemoryList: View {
  let lines: [Line<MemoryEntry>]
  let file: MemoryFile?
  @State private var forgotten: Set<String> = []

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
        MemoryRow(line: line, file: file, forgotten: $forgotten)
          .overlay(alignment: .top) {
            if index > 0 { Rectangle().fill(Palette.line).frame(height: Size.hairline).padding(.leading, 14) }
          }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.surface)
    .clipShape(shape)
    .cardShadow(shape)
  }
}

private struct MemoryRow: View {
  @Environment(\.host) private var host
  @Environment(\.openPage) private var openPage
  @Environment(\.showFailure) private var showFailure
  let line: Line<MemoryEntry>
  let file: MemoryFile?
  @Binding var forgotten: Set<String>
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        switch line {
        case .entry(let entry):
          Text(verbatim: entry.text)
          meta(entry)
        case .text(let text):
          Text(verbatim: text)
        }
      }
      .font(.system(size: 13.5))
      .lineSpacing(3)
      .foregroundStyle(Palette.ink)
      .frame(maxWidth: .infinity, alignment: .leading)
      if let file, case .entry(let entry) = line {
        forget(entry, in: file).opacity(hovering ? 1 : 0)
      }
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 14)
    .background(hovering ? Palette.fill : .clear)
    .onHover { hovering = $0 }
    .opacity(gone ? 0 : 1)
    .offset(x: gone ? 14 : 0)
    .animation(.easeOut(duration: 0.3), value: gone)
  }

  private var gone: Bool {
    if case .entry(let entry) = line { return forgotten.contains(entry.line) }
    return false
  }

  private func meta(_ entry: MemoryEntry) -> some View {
    HStack(spacing: Spacing.xs) {
      if let day = entry.day {
        Text(verbatim: day.short).font(.system(size: 10.5).monospaced()).foregroundStyle(Palette.inkFaint)
      }
      if let source = entry.source, let title = source.itemTitle, let page = Page(source.locator.content) {
        Button {
          openPage(page)
        } label: {
          Text(verbatim: title)
            .lineLimit(1)
            .truncationMode(.middle)
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.accentInk)
            .padding(.vertical, 1)
            .padding(.horizontal, 7)
            .background(Palette.tint, in: Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func forget(_ entry: MemoryEntry, in file: MemoryFile) -> some View {
    Button {
      forgotten.insert(entry.line)
      Task {
        do throws(HostError) {
          _ = try await host.run(Forget(entry.line, in: file))
        } catch {
          forgotten.remove(entry.line)
          showFailure(error)
        }
      }
    } label: {
      Image(systemName: Symbols.cancel)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Palette.inkMuted)
        .frame(width: 22, height: 22)
        .background(Circle().fill(Palette.fillStrong.opacity(hovering ? 1 : 0)))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .changesData()
    .help(Text(.loci("loci.forget")))
    .accessibilityLabel(Text(.loci("loci.forget")))
  }
}

/// What any conversation wrote down today, each line with its time and which conversation it came from.
private struct TodayNotes: View {
  let notes: [Line<DayNote>]

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      ForEach(Array(notes.enumerated()), id: \.offset) { _, line in
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
          switch line {
          case .entry(let note):
            Text(verbatim: note.time?.description ?? "")
              .font(.system(size: 11).monospaced())
              .foregroundStyle(Palette.inkFaint)
              .frame(width: 42, alignment: .leading)
            Text(joining: Text(verbatim: note.text).foregroundStyle(Palette.ink), from(note.from))
          case .text(let text):
            Text(verbatim: text).foregroundStyle(Palette.ink)
          }
        }
      }
    }
    .font(.system(size: 13))
    .lineSpacing(3)
    .padding(.vertical, Spacing.s)
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.well, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Radius.group, style: .continuous).strokeBorder(
        Palette.line, lineWidth: Size.hairline))
  }

  private func from(_ source: NoteSource?) -> Text {
    let name: Text? =
      switch source {
      case .main: Text(.loci("loci.fromMain"))
      case .item(_, let title?): Text(verbatim: title)
      case .review: Text(.loci("loci.fromReview"))
      case .run: Text(.loci("loci.fromRun"))
      case .course, .item(_, nil), nil: nil
      }
    guard let name else { return Text(verbatim: "") }
    return Text(joining: Text(verbatim: " · "), name).foregroundStyle(Palette.inkMuted)
  }
}
