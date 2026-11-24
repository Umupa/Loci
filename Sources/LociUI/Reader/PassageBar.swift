import AppKit
import LociModel
import SwiftUI

/// What can be done with a selected passage.
struct PassageActions {
  /// Highlights the passage at once and says which highlight it made, or `nil` when it could not.
  var highlight: (NSRange) async -> EntityID?
  /// Hands the passage to Loci's composer; `nil` where it cannot be asked about.
  var ask: ((NSRange) -> Void)?
  /// What can be done with the highlight once it is made.
  var note: NoteActions
  /// Whether the Mac behind the window can take changes now; the bar's buttons are off while it cannot.
  var changes = true
}

/// The glass bar over the text. Over a selection it offers to highlight or ask, as icons; over a highlight,
/// whether just made or clicked, it is a field for the thought with asking and deleting beside it.
struct PassageBar: View {
  enum Mode {
    case selection(NSRange)
    case note(EntityID, thought: String?)
  }

  let actions: PassageActions
  let mode: Mode
  /// Lets the bar take typing, once it shows the field for a thought.
  let typing: () -> Void
  let done: () -> Void
  @State private var made: EntityID?
  @State private var thought = ""
  @FocusState private var focused: Bool

  var body: some View {
    Group {
      if let note {
        noteBar(note)
      } else if case .selection(let range) = mode {
        HStack(spacing: 2) {
          GlassIconButton(symbol: Symbols.highlight, title: .loci("passage.highlight"), enabled: actions.changes) {
            Task {
              made = await actions.highlight(range)
              if made == nil { done() }
            }
          }
          if let ask = actions.ask {
            GlassIconButton(symbol: Symbols.ask, title: .loci("passage.ask")) {
              ask(range)
              done()
            }
          }
        }
      }
    }
    .padding(Spacing.xxs)
    .solidGlass(in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .fixedSize()
  }

  private var note: EntityID? {
    if case .note(let note, _) = mode { return note }
    return made
  }

  private var saved: String? {
    if case .note(_, let thought) = mode { return thought }
    return nil
  }

  private func noteBar(_ note: EntityID) -> some View {
    HStack(spacing: 2) {
      TextField(text: $thought) {
        Text(.loci("passage.thoughtPrompt"))
      }
      .textFieldStyle(.plain)
      .font(Typography.body)
      .focused($focused)
      .onSubmit { finish(note) }
      .onExitCommand(perform: done)
      .disabled(!actions.changes)
      .frame(width: Size.thoughtFieldWidth, height: Size.iconButton)
      .padding(.leading, Spacing.xs)
      Rectangle().fill(Palette.lineStrong).frame(width: Size.hairline, height: 18).padding(.horizontal, 3)
      if let ask = askNote(note) {
        GlassIconButton(symbol: Symbols.ask, title: .loci("passage.ask")) {
          ask()
          done()
        }
      }
      GlassIconButton(symbol: Symbols.delete, title: .loci("note.delete"), enabled: actions.changes) {
        actions.note.delete(note)
        done()
      }
    }
    .onAppear {
      thought = saved ?? ""
      typing()
      focused = true
    }
  }

  /// A highlight just made from the selection is asked about by the selection, which its quote came from.
  private func askNote(_ note: EntityID) -> (() -> Void)? {
    if case .selection(let range) = mode, let ask = actions.ask { return { ask(range) } }
    guard let ask = actions.note.ask else { return nil }
    return { ask(note) }
  }

  private func finish(_ note: EntityID) {
    let written = thought.trimmingCharacters(in: .whitespacesAndNewlines)
    let wanted = written.isEmpty ? nil : written
    if wanted != saved { actions.note.think(note, wanted) }
    done()
  }
}

/// A square icon in the glass bar, named by its tooltip.
struct GlassIconButton: View {
  let symbol: String
  let title: LocalizedStringResource
  var enabled = true
  var lit = false
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(!enabled ? Palette.inkFaint : lit ? Palette.accent : hovering ? Palette.ink : Palette.inkMuted)
        .frame(width: Size.iconButton, height: Size.iconButton)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(hovering && enabled ? Palette.fillStrong : .clear))
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .disabled(!enabled)
    .onHover { hovering = $0 }
    .help(Text(title))
    .accessibilityLabel(Text(title))
  }
}

/// Floats the `PassageBar` over a finished selection, in a borderless panel of its own: a popover would draw
/// its own frame and arrow around the glass. A click anywhere else puts it away.
///
/// The panel takes typing only once the bar asks for a thought, so until then the text keeps its window's
/// focus and its selection keeps its color.
@MainActor
final class PassagePopover {
  private var panel: PassagePanel?
  private var monitor: Any?

  /// Where a bar of `size` goes over a selection covering `lines`, in the text's flipped coordinates: just
  /// above its first line, so the lines after it stay in view, or under its last line when the top of
  /// `visible` leaves no room. It never leaves `visible` sideways.
  static func frame(of size: CGSize, over lines: [CGRect], within visible: CGRect) -> CGRect {
    guard let first = lines.first, let last = lines.last else { return .zero }
    let above = first.minY - Spacing.xxs - size.height
    let fitsAbove = above >= visible.minY
    let x = min(max(fitsAbove ? first.minX : last.minX, visible.minX), visible.maxX - size.width)
    return CGRect(origin: CGPoint(x: x, y: fitsAbove ? above : last.maxY + Spacing.xxs), size: size)
  }

  /// `locale` is the window's, which a panel of its own does not inherit.
  func show(
    _ actions: PassageActions, for range: NSRange, over lines: [CGRect], in view: NSView, locale: Locale
  ) {
    show(actions, .selection(range), over: lines, in: view, locale: locale)
  }

  /// The bar over a highlight that was clicked: its thought to change, asking, deleting.
  func show(
    _ actions: PassageActions, note: EntityID, thought: String?, over lines: [CGRect], in view: NSView,
    locale: Locale
  ) {
    show(actions, .note(note, thought: thought), over: lines, in: view, locale: locale)
  }

  private func show(
    _ actions: PassageActions, _ mode: PassageBar.Mode, over lines: [CGRect], in view: NSView, locale: Locale
  ) {
    close()
    guard let window = view.window else { return }
    let panel = PassagePanel()
    panel.appearance = window.effectiveAppearance
    let place = { [weak view, weak panel, weak window] (size: CGSize) in
      guard let view, let panel, let window, view.window === window else { return }
      let frame = Self.frame(of: size, over: lines, within: view.visibleRect)
      panel.setFrame(window.convertToScreen(view.convert(frame, to: nil)), display: true)
    }
    let host = NSHostingView(
      rootView: PassageBar(actions: actions, mode: mode, typing: { [weak panel] in panel?.makeKey() }) {
        [weak self] in self?.close()
      }
      .onGeometryChange(for: CGSize.self, of: \.size) { size in place(size) }
      .environment(\.locale, locale))
    host.sizingOptions = [.intrinsicContentSize]
    panel.contentView = host
    place(host.fittingSize)
    window.addChildWindow(panel, ordered: .above)
    panel.orderFront(nil)
    self.panel = panel
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      if event.window !== self?.panel { self?.close() }
      return event
    }
  }

  var isShown: Bool { panel != nil }

  func close() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    guard let panel else { return }
    panel.parent?.removeChildWindow(panel)
    panel.orderOut(nil)
    self.panel = nil
  }
}

/// A clear, borderless panel that can take typing, for the thought field.
private final class PassagePanel: NSPanel {
  init() {
    super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isReleasedWhenClosed = false
  }

  override var canBecomeKey: Bool { true }
}
