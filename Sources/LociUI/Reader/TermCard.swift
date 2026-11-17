import AppKit
import LociModel
import SwiftUI

/// A glossary term's definition, with a way to the lesson that teaches it.
struct TermCard: View {
  let term: Glossary.Term
  let open: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(verbatim: term.term).font(Typography.bodyEmphasis).foregroundStyle(Palette.ink)
      Text(verbatim: term.definition).font(Typography.body).foregroundStyle(Palette.ink)
        .fixedSize(horizontal: false, vertical: true)
      if term.lesson != nil {
        Button(action: open) {
          Text(.loci("term.openLesson"))
        }
        .buttonStyle(.link)
        .foregroundStyle(Palette.accentInk)
      }
    }
    .padding(Spacing.s)
    .frame(width: Size.termCardWidth, alignment: .leading)
  }
}

/// Shows one `TermCard` at a time beside the term under the pointer.
@MainActor
final class TermPopover {
  private var popover: NSPopover?
  private var shown: (term: Glossary.Term, rect: CGRect)?
  private var closing: Task<Void, Never>?
  /// How long the card stays after the pointer leaves the term, so the pointer can reach it.
  private static let grace = Duration.milliseconds(350)

  func show(_ term: Glossary.Term, at rect: CGRect, in view: NSView, open: @escaping () -> Void) {
    closing?.cancel()
    closing = nil
    guard shown?.term != term || shown?.rect != rect else { return }
    close()
    let popover = NSPopover()
    popover.behavior = .semitransient
    popover.animates = false
    popover.contentViewController = NSHostingController(
      rootView: TermCard(term: term) { [weak self] in
        self?.close()
        open()
      })
    popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    self.popover = popover
    shown = (term, rect)
  }

  /// Puts the card away once the pointer has been off both the term and the card for a moment.
  func closeSoon() {
    guard popover != nil, closing == nil else { return }
    closing = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.grace)
        guard !Task.isCancelled, let self else { return }
        if self.popover?.contentViewController?.view.window?.frame.contains(NSEvent.mouseLocation) != true {
          self.close()
          return
        }
      }
    }
  }

  func close() {
    closing?.cancel()
    closing = nil
    popover?.close()
    popover = nil
    shown = nil
  }
}
