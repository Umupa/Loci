import LociModel
import SwiftUI

/// A list in a panel: each line on its own faint block, opening its link when clicked. Lines the person hid
/// are left out and pinned ones come first, with the person's note under them.
struct PanelList: View {
  let items: [PanelListItem]
  let actions: PanelActions
  @Environment(\.panelEditing) private var editing
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    let lines = MarkedLines(items, marks: editing?.marks ?? [:]).shown
    VStack(spacing: Spacing.xs) {
      ForEach(Array(lines.enumerated()), id: \.offset) { _, marked in
        MarkedLine(line: marked.line, mark: marked.mark, actions: actions, editing: editing).panelRow()
      }
    }
    .animation(reduceMotion ? nil : Motion.standard, value: lines.map { PanelLineKey($0.line) })
  }
}

/// One line of a list in a panel, with the person's take on it, which right-clicking changes.
private struct MarkedLine: View {
  let line: PanelListItem
  let mark: PanelLineMark
  let actions: PanelActions
  let editing: PanelEditing?
  @State private var noting: String?
  @FocusState private var typing: Bool

  var body: some View {
    PanelLine(
      title: line.title, subtitle: line.subtitle, at: line.at, number: line.number, progress: line.progress,
      pinned: mark.pinned, ask: line.ask.map { words in { actions.ask(words) } },
      open: line.link.map { link in { actions.open(link) } }
    ) {
      if let cover = line.cover { PanelCover(url: cover) }
    } aside: {
      if let noting {
        TextField("", text: Binding(get: { noting }, set: { self.noting = $0 }), axis: .vertical)
          .textFieldStyle(.plain)
          .font(ItemNote.font)
          .foregroundStyle(Palette.inkMuted)
          .focused($typing)
          .onSubmit { finish(keep: true) }
          .onExitCommand { finish(keep: false) }
          .onChange(of: typing) { if !typing { finish(keep: true) } }
          .onAppear { typing = true }
      } else if let note = mark.note {
        ItemNote(text: note)
      }
    }
    .contextMenu {
      if editing != nil {
        ForEach(PanelLineMenu.entries(for: mark), id: \.self) { entry in
          if entry == .hide { Divider() }
          Button {
            choose(entry)
          } label: {
            Text(entry.name)
          }
        }
      }
    }
  }

  private func choose(_ entry: PanelLineMenu) {
    var changed = mark
    switch entry {
    case .pin, .unpin:
      changed.pinned.toggle()
      editing?.mark(PanelLineKey(line), changed)
    case .note, .editNote: noting = mark.note ?? ""
    case .hide:
      changed.hidden = true
      editing?.mark(PanelLineKey(line), changed)
    }
  }

  private func finish(keep: Bool) {
    guard let words = noting?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
    noting = nil
    guard keep, words != (mark.note ?? "") else { return }
    var changed = mark
    changed.note = words.isEmpty ? nil : words
    editing?.mark(PanelLineKey(line), changed)
  }
}

/// One line of a list, as both Loci's panels and 「接着读」 draw it: a rank, a cover, the title over a subtitle
/// and a progress bar, when it happened or a pin, and 「问 Loci」.
struct PanelLine<Cover: View, Aside: View>: View {
  let title: String
  var subtitle: String?
  var at: String?
  var number: Int?
  var progress: Double?
  var pinned = false
  var ask: (() -> Void)?
  var open: (() -> Void)?
  @ViewBuilder var cover: Cover
  /// Under the title: the person's note.
  @ViewBuilder var aside: Aside
  @State private var pointed = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.panelBlock, style: .continuous)
    HStack(alignment: .top, spacing: 10) {
      if let number {
        Text(verbatim: "\(number)").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink.opacity(0.35))
          .frame(width: 18, alignment: .leading)
      }
      cover
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: title).font(.system(size: 14)).lineSpacing(2).foregroundStyle(Palette.ink)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(verbatim: subtitle).font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.5)).lineLimit(1)
        }
        if let progress { PanelProgress(progress: progress).padding(.top, 5) }
        aside
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if pinned {
        PinMark().padding(.top, 3)
      } else if let at {
        Text(verbatim: at).font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.45)).padding(.top, 1)
      }
      if let ask { AskButton(action: ask) }
    }
    .padding(.vertical, 11)
    .padding(.horizontal, Spacing.s)
    .background(Palette.ink.opacity(pointed && open != nil ? 0.08 : 0.05), in: shape)
    .contentShape(shape)
    .onHover { pointed = $0 }
    .onTapGesture { open?() }
    .pointerStyle(open == nil ? nil : .link)
  }
}

extension PanelLine where Aside == EmptyView {
  init(
    title: String, subtitle: String? = nil, at: String? = nil, number: Int? = nil, progress: Double? = nil,
    ask: (() -> Void)? = nil, open: (() -> Void)? = nil, @ViewBuilder cover: () -> Cover
  ) {
    self.init(
      title: title, subtitle: subtitle, at: at, number: number, progress: progress, ask: ask, open: open,
      cover: cover, aside: { EmptyView() })
  }
}

/// How far along something is: a thin amber line on a faint track.
private struct PanelProgress: View {
  let progress: Double

  var body: some View {
    Capsule().fill(Palette.ink.opacity(0.1))
      .overlay(alignment: .leading) {
        GeometryReader { track in
          Capsule().fill(Palette.accent).frame(width: track.size.width * min(max(progress, 0), 1))
        }
      }
      .frame(height: 3)
  }
}

private struct AskButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(.loci("panels.ask")).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(Palette.ink.opacity(0.08), in: .capsule)
        .contentShape(.capsule)
    }
    .buttonStyle(PressStyle(scale: 0.94))
    .changesData()
  }
}

/// A picture before a list line's title, read by its address.
private struct PanelCover: View {
  let url: URL
  @Environment(\.panelPictures) private var pictures
  @Environment(\.host) private var host

  var body: some View {
    Group {
      if let image = pictures?.image(of: url) {
        Image(nsImage: image).resizable().scaledToFill()
      } else {
        Palette.ink.opacity(0.08)
      }
    }
    .frame(width: Size.panelCover, height: Size.panelCover)
    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    .task(id: url) { await pictures?.load(url, from: host) }
  }
}
