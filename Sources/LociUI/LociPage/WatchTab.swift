import LociModel
import SwiftUI

/// What each home watches for: the chat and the projects on the left, and on the right a sheet with the
/// chosen one's `WATCH.md`, which the person can rewrite (WT-S12).
struct WatchTab: View {
  @State private var chosen: Home
  @State private var bar: Feed<ProjectBar>?
  @State private var width: CGFloat = 0
  @Environment(\.reducesMotion) private var reduceMotion

  static let columns = PageColumns(
    spacing: 34, stackedSpacing: 28, narrowestFirst: 220, second: 420...720, share: 0.68)

  /// `chosen` starts with that home's watch open.
  init(chosen: Home = .chat) {
    _chosen = State(initialValue: chosen)
  }

  private var projects: [Project] { bar?.value?.projects ?? [] }

  var body: some View {
    Self.columns {
      VStack(alignment: .leading, spacing: 0) {
        WatchHomeRow(chosen: chosen == .chat, tie: sideBySide, choose: { choose(.chat) }) {
          LociAvatar(size: 22)
          Text(.loci("projects.chat"))
        }
        ForEach(projects) { project in
          WatchHomeRow(
            chosen: chosen == .project(project.id), tie: sideBySide, choose: { choose(.project(project.id)) }
          ) {
            ProjectSeal(symbol: project.symbol, size: 22, locked: !project.remembered)
            project.title
          }
        }
      }
      WatchSheet(home: chosen, title: title).id(chosen).transition(.opacity)
    }
    .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    .subscribing(WatchProjects(), into: $bar)
  }

  private var sideBySide: Bool { Self.columns.widths(for: width) != nil }

  private var title: Text {
    switch chosen {
    case .chat: Text(.loci("projects.chat"))
    case .project(let id): projects.first { $0.id == id }?.title ?? Text(verbatim: "")
    }
  }

  private func choose(_ home: Home) {
    withAnimation(reduceMotion ? nil : Motion.standard) { chosen = home }
  }

  /// The file without the heading every one starts with, which the sheet's title already says.
  static func shown(_ text: String) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    if lines.first?.hasPrefix("# ") == true { lines.removeFirst() }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// A home in the list: its face and name, washed while it is the one open, tied by a thread to the sheet.
private struct WatchHomeRow<Label: View>: View {
  let chosen: Bool
  let tie: Bool
  let choose: () -> Void
  @ViewBuilder let label: Label
  @State private var hovering = false

  var body: some View {
    Button(action: choose) {
      HStack(spacing: 10) { label }
        .font(.system(size: 14))
        .foregroundStyle(Palette.ink)
        .lineLimit(1)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(chosen ? Palette.fillStrong : hovering ? Palette.fill : .clear)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .overlay(alignment: .trailing) {
      if chosen, tie {
        Rectangle().fill(Palette.ink.opacity(0.3)).frame(width: 30, height: 1.5).offset(x: 34)
          .accessibilityHidden(true)
      }
    }
    .accessibilityAddTraits(chosen ? .isSelected : [])
  }
}

/// One home's `WATCH.md` on a sheet, kept current as the companion or the person changes the file, with a
/// button to rewrite it.
private struct WatchSheet: View {
  let home: Home
  let title: Text
  @Environment(\.host) private var host
  @Environment(\.showFailure) private var showFailure
  @State private var notes: Feed<String>?
  @State private var editing: String?

  var body: some View {
    MemorySheet(title: title) {
      VStack(alignment: .leading, spacing: 14) {
        if let editing {
          editor(editing)
        } else if let text = notes?.value {
          let shown = WatchTab.shown(text)
          if shown.isEmpty {
            Image(systemName: "eye").font(.system(size: 22, weight: .light)).foregroundStyle(Palette.inkFaint)
              .frame(maxWidth: .infinity, minHeight: 64)
              .accessibilityHidden(true)
          } else {
            SerifProse(markdown: shown)
          }
          PageButton(title: .loci("loci.edit")) { editing = text }.changesData()
        }
      }
    }
    .subscribing(WatchNotes(of: home), into: $notes)
  }

  private func editor(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      TextEditor(text: Binding(get: { text }, set: { editing = $0 }))
        .font(.system(size: 14).monospaced())
        .scrollContentBackground(.hidden)
        .padding(Spacing.s)
        .frame(minHeight: 320)
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
            .strokeBorder(Palette.line, lineWidth: Size.hairline))
      HStack(spacing: Spacing.xs) {
        PageButton(title: .loci("loci.save")) { save(text) }.changesData()
        PageButton(title: .loci("dialog.cancel")) { editing = nil }
      }
    }
  }

  private func save(_ text: String) {
    Task {
      do throws(HostError) {
        _ = try await host.run(SaveWatch(text, in: home))
        editing = nil
      } catch {
        showFailure(error)
      }
    }
  }
}
