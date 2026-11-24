import AppKit
import LociModel
import SwiftUI

/// The small glass bar in the top corner of a picture under the mouse: highlight it, or ask Loci about it.
/// On a picture already highlighted the highlight icon is amber.
struct PictureTools: View {
  let marked: Bool
  let changes: Bool
  let highlight: () -> Void
  let ask: (() -> Void)?
  @Environment(\.reducesMotion) private var reducesMotion
  @State private var appeared = false

  var body: some View {
    HStack(spacing: 2) {
      GlassIconButton(
        symbol: Symbols.highlight, title: .loci("passage.highlight"), enabled: changes, lit: marked, action: highlight)
      if let ask {
        GlassIconButton(symbol: Symbols.ask, title: .loci("passage.askPicture"), action: ask)
      }
    }
    .padding(3)
    .solidGlass(in: RoundedRectangle(cornerRadius: Radius.row + 2, style: .continuous))
    .fixedSize()
    .opacity(appeared ? 1 : 0)
    .scaleEffect(appeared ? 1 : 0.96, anchor: .topTrailing)
    .offset(y: appeared ? 0 : -4)
    .onAppear {
      if reducesMotion {
        appeared = true
      } else {
        withAnimation(Motion.quick) { appeared = true }
      }
    }
  }
}

/// Keeps the `PictureTools` over the picture the mouse is on, inside the text view so it scrolls with it.
@MainActor
final class PictureToolsHost {
  private var shown: (spot: ReaderPictureSpot, view: NSView)?
  private static let inset: CGFloat = 10

  /// `marked` is the highlight the picture is in, if it is in one.
  func show(
    _ spot: ReaderPictureSpot, marked: EntityID?, in textView: ReaderTextView, actions: PassageActions,
    locale: Locale, chose: @escaping (EntityID) -> Void, highlighted: @escaping (EntityID) -> Void
  ) {
    hide()
    let tools = PictureTools(
      marked: marked != nil, changes: actions.changes,
      highlight: { [weak textView] in
        if let marked {
          chose(marked)
          return
        }
        Task { @MainActor in
          guard let note = await actions.highlight(spot.range) else { return }
          textView?.sweep(spot.frame)
          highlighted(note)
        }
      },
      ask: actions.ask.map { ask in { ask(spot.range) } }
    )
    let view = NSHostingView(rootView: tools.environment(\.locale, locale))
    view.sizingOptions = [.intrinsicContentSize]
    let size = view.fittingSize
    view.frame = CGRect(
      x: spot.frame.maxX - Self.inset - size.width, y: spot.frame.minY + Self.inset, width: size.width,
      height: size.height)
    textView.addSubview(view)
    shown = (spot, view)
  }

  var spot: ReaderPictureSpot? { shown?.spot }

  func hide() {
    shown?.view.removeFromSuperview()
    shown = nil
  }
}
