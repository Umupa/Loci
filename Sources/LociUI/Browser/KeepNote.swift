import LociModel
import SwiftUI

/// Under the library button once what was kept has a result: saved, with opening it and taking it back out;
/// or not saved, with why and what gets it going again.
struct KeepNote: View {
  let state: Keeping.State
  let act: (Act) -> Void

  enum Act {
    case open(EntityID)
    case undo
    case fix(Item, JobLine.Fix)
    case keepAgain
    case putAway
  }

  var body: some View {
    HStack(spacing: Spacing.s) {
      Image(systemName: saved ? Symbols.done : Symbols.problem)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Palette.accent)
      words
        .font(Typography.control)
        .foregroundStyle(Palette.ink)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      actions
    }
    .padding(.leading, Spacing.m)
    .padding(.trailing, Spacing.xs)
    .padding(.vertical, Spacing.xs)
    .frame(minHeight: 40)
    .frame(maxWidth: 420)
    .fixedSize(horizontal: true, vertical: false)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.floating)
        .shadow(color: .black.opacity(0.22), radius: 20, y: 12)
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
    )
  }

  private var saved: Bool {
    if case .saved = state { true } else { false }
  }

  @ViewBuilder private var words: some View {
    switch state {
    case .saved(let items) where items.count > 1: Text(.loci("overlay.savedSome \(items.count)"))
    case .saved, .saving: Text(.loci("overlay.saved"))
    case .stopped(_, let fix, let problem): fix.why(problem) ?? Text(.loci("overlay.notSaved"))
    case .refused(let error): Text(Messages.describe(error))
    }
  }

  @ViewBuilder private var actions: some View {
    switch state {
    case .saved(let items):
      if let only = items.first, items.count == 1 { quiet(Text(.loci("overlay.open"))) { act(.open(only.id)) } }
      quiet(Text(.loci("library.undo"))) { act(.undo) }
    case .saving:
      EmptyView()
    case .stopped(let item, let fix, _):
      Button {
        act(.fix(item, fix))
      } label: {
        fix.label
      }
      .buttonStyle(AmberButtonStyle())
      .changesData(fix.changesData)
      putAway
    case .refused:
      Button {
        act(.keepAgain)
      } label: {
        Text(.loci("job.retry"))
      }
      .buttonStyle(AmberButtonStyle())
      .changesData()
      putAway
    }
  }

  private func quiet(_ label: Text, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      label
        .font(Typography.control.weight(.semibold))
        .foregroundStyle(Palette.accentInk)
        .padding(.horizontal, Spacing.xxs)
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
  }

  private var putAway: some View {
    IconButton(symbol: Symbols.cancel, title: .loci("overlay.close"), size: 24, symbolSize: 10, tint: Palette.inkMuted)
    {
      act(.putAway)
    }
  }
}

/// Where the note shows under the library button, doing what its buttons say. A saved note goes after a few
/// seconds; a stopped one stays until it is put away.
struct KeepNoteSlot: View {
  let keeping: PageKeeping
  let state: Keeping.State?
  let session: BrowserSession
  let keepAgain: ([PageFinds.Find]) -> Void
  var opening: () -> Void = {}
  @Environment(\.host) private var host
  @Environment(\.openPage) private var openPage
  @Environment(\.openPlace) private var openPlace
  @Environment(\.showFailure) private var showFailure
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    ZStack(alignment: .topTrailing) {
      if keeping.noteUp, let state, Self.tells(state) {
        KeepNote(state: state, act: act)
          .transition(reduceMotion ? .identity : .scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity))
          .task(id: state) {
            guard case .saved = state, (try? await Task.sleep(for: PageKeeping.savedNoteTime)) != nil else { return }
            withAnimation(reduceMotion ? nil : Motion.quick) { keeping.putAway(state) }
          }
      }
    }
    .animation(reduceMotion ? nil : Motion.quick, value: keeping.noteUp)
  }

  /// Saving is told on the button alone.
  private static func tells(_ state: Keeping.State) -> Bool {
    if case .saving = state { false } else { true }
  }

  private func act(_ act: KeepNote.Act) {
    switch act {
    case .open(let item):
      keeping.putAway(state)
      opening()
      openPage(.item(item))
    case .undo:
      keeping.undo(with: host)
    case .fix(let item, let fix):
      JobFixes(host: host, openPlace: openPlace, browser: session, failed: showFailure, changesAllowed: changesAllowed)
        .apply(fix, to: item)
      if !fix.changesData { keeping.putAway(state) }
    case .keepAgain:
      keepAgain(keeping.keeping?.chosen ?? [])
    case .putAway:
      keeping.putAway(state)
    }
  }
}
