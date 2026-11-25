import LociModel
import SwiftUI

/// What the companion remembers: its index on the left, each line linking to a page of its wiki, and who the
/// person is under it; on the right a sheet with the page opened, or today's notes when none is. Ink and gray,
/// with no headings (ME-S7).
struct MemoryTab: View {
  let memory: [Line<MemoryEntry>]
  let profile: [Line<MemoryEntry>]
  let today: DayNotes
  @State private var opened: String?
  @State private var width: CGFloat = 0
  @Environment(\.reducesMotion) private var reduceMotion

  static let columns = PageColumns(
    spacing: 34, stackedSpacing: 28, narrowestFirst: 320, second: 340...620, share: 0.52)

  /// `opened` starts with that page of the wiki open.
  init(memory: [Line<MemoryEntry>], profile: [Line<MemoryEntry>], today: DayNotes, opened: String? = nil) {
    self.memory = memory
    self.profile = profile
    self.today = today
    _opened = State(initialValue: opened)
  }

  private var sideBySide: Bool { Self.columns.widths(for: width) != nil }

  var body: some View {
    Self.columns {
      MemoryIndex(memory: memory, profile: profile, opened: opened, tie: sideBySide, open: open)
      Group {
        if let opened {
          WikiSheet(name: opened, open: open).id(opened)
        } else {
          TodaySheet(today: today)
        }
      }
      .transition(.opacity)
    }
    .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
  }

  private func open(_ page: String?) {
    withAnimation(reduceMotion ? nil : Motion.standard) { opened = page == opened ? nil : page }
  }
}

/// The index and the person's profile under it, or a dashed outline when nothing is remembered yet.
private struct MemoryIndex: View {
  let memory: [Line<MemoryEntry>]
  let profile: [Line<MemoryEntry>]
  let opened: String?
  /// Whether a thread ties the opened line to the sheet beside it.
  let tie: Bool
  let open: (String?) -> Void

  var body: some View {
    if memory.isEmpty && profile.isEmpty {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .frame(height: 132)
        .overlay {
          Image(systemName: "doc.text").font(.system(size: 22, weight: .light)).foregroundStyle(Palette.inkFaint)
        }
        .accessibilityHidden(true)
    } else {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(memory.enumerated()), id: \.offset) { _, line in
          MemoryLine(line: line, forget: .index, opened: opened, tie: tie, open: open)
        }
        if !memory.isEmpty && !profile.isEmpty {
          Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 14).padding(.horizontal, 12)
        }
        ForEach(Array(profile.enumerated()), id: \.offset) { _, line in
          MemoryLine(line: line, forget: nil, opened: nil, tie: false, open: open, muted: true)
        }
      }
    }
  }
}

/// A sheet of paper beside the index: a thin rule down its margin, a serif title, and its lines.
struct MemorySheet<Content: View>: View {
  let title: Text
  @ViewBuilder let content: Content

  var body: some View {
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 14, topTrailingRadius: 14,
      style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      title.font(.system(size: 24, weight: .semibold, design: .serif)).padding(.bottom, 14)
      content
    }
    .padding(.top, 26)
    .padding(.bottom, 22)
    .padding(.leading, 34)
    .padding(.trailing, 30)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(alignment: .leading) {
      Rectangle().fill(Palette.line).frame(width: 1.5).padding(.vertical, 22).padding(.leading, 14)
    }
    .background(Palette.surface, in: shape)
    .overlay(shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
  }
}

/// A page of the wiki, kept current, its links to other pages opening them.
private struct WikiSheet: View {
  let name: String
  let open: (String?) -> Void
  @State private var page: Feed<WikiPage>?

  var body: some View {
    MemorySheet(title: Text(verbatim: page?.value?.title ?? name)) {
      if let lines = page?.value?.lines {
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
          MemoryLine(line: line, forget: .page(name), opened: nil, tie: false, open: open, onSheet: true)
            .rule(index > 0)
        }
      }
    }
    .subscribing(WatchWikiPage(name), into: $page)
  }
}

/// What any session wrote down today, each line with its time and where it came from.
private struct TodaySheet: View {
  let today: DayNotes

  var body: some View {
    MemorySheet(title: Text(.loci("loci.today"))) {
      if today.notes.isEmpty {
        Image(systemName: "text.alignleft").font(.system(size: 22, weight: .light)).foregroundStyle(Palette.inkFaint)
          .frame(maxWidth: .infinity, minHeight: 64)
          .accessibilityHidden(true)
      }
      ForEach(Array(today.notes.enumerated()), id: \.offset) { index, line in
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          switch line {
          case .entry(let note):
            Text(verbatim: note.time?.description ?? "")
              .font(.system(size: 11.5).monospaced()).foregroundStyle(Palette.inkFaint).frame(
                width: 38, alignment: .leading)
            Text(joining: Text(verbatim: note.text).foregroundStyle(Palette.ink), Self.from(note.from))
          case .text(let text):
            Text(verbatim: text).foregroundStyle(Palette.ink)
          }
        }
        .font(.system(size: 14))
        .lineSpacing(3)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rule(index > 0)
      }
    }
  }

  static func from(_ source: NoteSource?) -> Text {
    let name: Text? =
      switch source {
      case .main: Text(.loci("loci.fromMain"))
      case .item(_, let title?): Text(verbatim: title)
      case .review: Text(.loci("loci.fromReview"))
      case .run: Text(.loci("loci.fromRun"))
      case .course, .project, .item(_, nil), nil: nil
      }
    guard let name else { return Text(verbatim: "") }
    return Text(joining: Text(verbatim: " · "), name).font(.system(size: 12)).foregroundStyle(Palette.inkFaint)
  }
}
