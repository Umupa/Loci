import AppKit
import LociModel
import SwiftUI

/// What can be done with a selected passage.
struct PassageActions {
  /// Highlights the passage at once and says which highlight it made, or `nil` when it could not.
  var highlight: (NSRange) async -> EntityID?
  var think: (EntityID, String) -> Void
  /// Hands the passage to Loci's composer; `nil` where it cannot be asked about.
  var ask: ((NSRange) -> Void)?
  /// Whether the Mac behind the window can take changes now; the bar's buttons are off while it cannot.
  var changes = true
}

/// The glass capsule over a selection: highlight it, or ask Loci. Highlighting turns the capsule into
/// a field for a thought, which may be left empty.
struct PassageBar: View {
  let actions: PassageActions
  let range: NSRange
  /// Lets the bar take typing, once it turns into the field for a thought.
  let typing: () -> Void
  let done: () -> Void
  @State private var note: EntityID?
  @State private var thought = ""
  @FocusState private var focused: Bool

  var body: some View {
    Group {
      if let note {
        TextField(text: $thought) {
          Text(.loci("passage.thoughtPrompt"))
        }
        .textFieldStyle(.plain)
        .font(Typography.body)
        .focused($focused)
        .onSubmit { finish(note) }
        .onExitCommand(perform: done)
        .frame(width: Size.thoughtFieldWidth, height: Size.iconButton)
        .padding(.horizontal, Spacing.s)
        .onAppear {
          typing()
          focused = true
        }
      } else {
        HStack(spacing: 0) {
          button(.loci("passage.highlight"), Symbols.highlight) {
            Task {
              note = await actions.highlight(range)
              if note == nil { done() }
            }
          }
          if let ask = actions.ask {
            Rectangle().fill(Palette.lineStrong).frame(width: Size.hairline, height: Spacing.m)
            button(.loci("passage.ask"), Symbols.ask) {
              ask(range)
              done()
            }
          }
        }
      }
    }
    .padding(Spacing.xxs)
    .solidGlass(in: Capsule())
    .fixedSize()
  }

  private func button(_ title: LocalizedStringResource, _ symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: symbol).font(Typography.body).foregroundStyle(
          actions.changes ? Palette.accent : Palette.inkFaint)
        Text(title)
      }
      .font(Typography.bodyEmphasis)
      .foregroundStyle(actions.changes ? Palette.ink : Palette.inkFaint)
      .padding(.horizontal, Spacing.s)
      .frame(height: Size.iconButton)
      .contentShape(Capsule())
    }
    .buttonStyle(PressStyle())
    .disabled(!actions.changes)
  }

  private func finish(_ note: EntityID) {
    let written = thought.trimmingCharacters(in: .whitespacesAndNewlines)
    if !written.isEmpty { actions.think(note, written) }
    done()
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
      rootView: PassageBar(actions: actions, range: range, typing: { [weak panel] in panel?.makeKey() }) {
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
