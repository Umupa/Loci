import LociModel
import SwiftUI

/// Where a remembered line can be forgotten from.
enum ForgetPlace: Equatable {
  /// `MEMORY.md`.
  case index
  /// A page of the wiki.
  case page(String)
}

/// One remembered line: its day, its words, the page it links to and where it came from. Under the pointer it
/// offers to be forgotten; clicked, it opens the page it links to.
struct MemoryLine: View {
  @Environment(\.host) private var host
  @Environment(\.openPage) private var openPage
  @Environment(\.showFailure) private var showFailure
  let line: Line<MemoryEntry>
  /// `nil` for a line that cannot be forgotten here, such as the person's profile.
  let forget: ForgetPlace?
  /// The page open beside the index.
  let opened: String?
  /// Whether the opened line is tied by a thread to the sheet beside it.
  let tie: Bool
  let open: (String?) -> Void
  var muted = false
  /// Lines on a sheet sit flush, with no wash of their own.
  var onSheet = false
  @Environment(\.pointedMemoryLine) private var pointed
  @State private var pointer = false
  @State private var gone = false

  private var hovering: Bool { pointer || (pointed != nil && pointed == entry?.line) }

  private var entry: MemoryEntry? {
    if case .entry(let entry) = line { entry } else { nil }
  }

  private var selected: Bool { entry?.page.map { $0.name == opened } ?? false }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(verbatim: entry?.day?.short ?? "")
        .font(.system(size: 11.5).monospaced())
        .foregroundStyle(Palette.inkFaint)
        .frame(width: 38, alignment: .leading)
      VStack(alignment: .leading, spacing: 4) {
        words.font(.system(size: 14)).lineSpacing(3).foregroundStyle(muted ? Palette.inkMuted : Palette.ink)
        if let source = entry?.source, let title = source.itemTitle { sourceChip(title, source.locator) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, onSheet ? 8 : 9)
    .padding(.horizontal, onSheet ? 0 : 12)
    .background {
      if !onSheet {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(selected ? Palette.fillStrong : hovering ? Palette.fill : .clear)
      }
    }
    .overlay(alignment: .topTrailing) {
      if let forget, let entry, hovering {
        forgetButton(entry, from: forget)
          .padding(.leading, 10)
          .background(onSheet ? Palette.surface : .clear)
          .padding(.top, onSheet ? 6 : 7)
          .padding(.trailing, onSheet ? 0 : 8)
      }
    }
    .overlay(alignment: .trailing) {
      if selected, tie {
        Rectangle().fill(Palette.ink.opacity(0.3)).frame(width: 30, height: 1.5).offset(x: 34)
          .accessibilityHidden(true)
      }
    }
    .contentShape(Rectangle())
    .onHover { pointer = $0 }
    .onTapGesture { if let page = entry?.page { open(page.name) } }
    .opacity(gone ? 0 : 1)
    .animation(.easeOut(duration: 0.3), value: gone)
    .accessibilityAddTraits(entry?.page == nil ? [] : .isButton)
  }

  /// The words, then the page they link to, underlined in ink.
  private var words: Text {
    switch line {
    case .text(let text): return Text(verbatim: text)
    case .entry(let entry):
      guard let page = entry.page else { return Text(verbatim: entry.text) }
      let tag = Text(joining: Text(Image(systemName: "doc")), Text(verbatim: " " + page.title))
        .font(.system(size: 12.5))
        .foregroundStyle(Palette.ink)
        .underline(color: selected ? Palette.ink : Palette.lineStrong)
      return Text(joining: Text(verbatim: entry.text + "  "), tag)
    }
  }

  private func sourceChip(_ title: String, _ locator: Locator) -> some View {
    Button {
      if let page = Page(locator.content) { openPage(page) }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: Symbols.library).font(.system(size: 10))
        Text(verbatim: title).lineLimit(1).truncationMode(.middle)
      }
      .font(.system(size: 12))
      .foregroundStyle(Palette.inkMuted)
      .padding(.vertical, 1)
      .padding(.horizontal, 7)
      .background(Palette.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func forgetButton(_ entry: MemoryEntry, from place: ForgetPlace) -> some View {
    Button {
      gone = true
      Task {
        do throws(HostError) {
          switch place {
          case .index: _ = try await host.run(Forget(entry.line, in: .memory))
          case .page(let name): _ = try await host.run(ForgetWikiLine(entry.line, on: name))
          }
        } catch {
          gone = false
          showFailure(error)
        }
      }
    } label: {
      Text(.loci("loci.forget"))
    }
    .buttonStyle(ForgetPill())
    .changesData()
  }
}

/// A small gray pill that turns to ink under the pointer.
private struct ForgetPill: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    Face(configuration: configuration)
  }

  private struct Face: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
      configuration.label
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(hovering ? Palette.canvas : Palette.inkMuted)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(hovering ? Palette.ink : Palette.fill))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
        .animation(Motion.quick, value: hovering)
    }
  }
}

extension EnvironmentValues {
  /// A remembered line shown as if the pointer were on it, by `MemoryEntry.line`, for pictures of the page.
  @Entry var pointedMemoryLine: String?
}
