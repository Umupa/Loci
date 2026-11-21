import LociModel
import SwiftUI

/// The main conversation with Loci, where the window opens, with the panel column on its right. A link or a
/// file dropped anywhere on it goes into the library.
struct TalkScreen: View {
  @Environment(\.openPage) private var openPage
  @Environment(\.browser) private var browser
  @Environment(\.openPlace) private var openPlace
  @Environment(\.host) private var host
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.changesAllowed) private var changesAllowed
  let focusRequest: Int
  let attach: () -> Void
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  /// The panel column, once the host has it; without it the conversation has the room to itself.
  let panels: Panels?
  /// Whether the person left the panel column showing.
  @Binding var columnPreferred: Bool
  @State private var draft: PassageDraft?
  @State private var newPanel: NewPanel?
  @State private var fill: ComposerFill?
  @State private var working = false
  @State private var fit = PaneFit.panelColumn

  var body: some View {
    HStack(spacing: 0) {
      ConversationScreen(
        ref: .main, draft: $draft, revealPassage: { openPage(Page($0.content)) }, attach: attach,
        focusRequest: focusRequest, panelRequest: panelRequest
      )
      if let panels, fit.shows(columnPreferred) {
        PanelColumnView(
          column: panels.column, building: building, making: newPanel == .asking, actions: actions(panels)
        )
        .frame(width: Size.panelColumn)
        .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
      }
    }
    .overlay(alignment: .topTrailing) {
      if panels != nil {
        PanelColumnToggle(shown: fit.shows(columnPreferred), toggle: toggleColumn)
          .padding(.trailing, Spacing.m)
          .padding(.top, 14)
      }
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: { width in
      var next = fit
      next.fit(width: width)
      guard next != fit else { return }
      withAnimation(reduceMotion ? nil : Motion.fold) { fit = next }
    }
    .onChange(of: panels?.column.panelNames) { settle() }
    .onChange(of: working) { settle() }
    .acceptingDrops()
  }

  /// What marks the skeleton of the panel being made, while one is.
  private var building: PanelSources? {
    if case .building(_, _, let sources) = newPanel { sources } else { nil }
  }

  private func toggleColumn() {
    withAnimation(reduceMotion ? nil : Motion.fold) { columnPreferred = fit.toggle(columnPreferred) }
  }

  private func settle() {
    newPanel = newPanel?.settled(names: panels?.column.panelNames ?? [], working: working)
  }

  private var panelRequest: PanelRequest {
    PanelRequest(
      making: Binding(
        get: { newPanel == .asking },
        set: { asking in
          if asking {
            newPanel = .asking
          } else if newPanel == .asking {
            newPanel = nil
          }
        }),
      made: { typed in
        newPanel = .building(
          known: panels?.column.panelNames ?? [], started: working,
          sources: PanelSources.named(in: typed, locale: locale))
      },
      fill: fill,
      working: { working = $0 })
  }

  private func actions(_ panels: Panels) -> PanelActions {
    PanelActions(
      open: open, openItem: { openPage(.item($0)) },
      ask: ask,
      create: { newPanel = .asking },
      revise: { panel in fill = .revising(panel, serial: (fill?.serial ?? 0) + 1, locale: locale) },
      refresh: panels.refresh, moveToTop: panels.moveToTop, remove: panels.remove)
  }

  /// Says `words` in the main conversation, as the person.
  private func ask(_ words: String) {
    guard changesAllowed else { return }
    Task {
      do throws(HostError) {
        _ = try await host.run(SendMessage(to: .main, text: words, passage: nil))
      } catch {
        failed(error)
      }
    }
  }

  /// A web page opens in the built-in browser; a `loci://` place opens that item.
  private func open(_ url: URL) {
    if let locator = Locator(url.absoluteString) {
      openPage(Page(locator.content))
    } else if url.isWebLink {
      OpenLink(browser: browser, openPlace: openPlace)(url)
    }
  }
}

/// The panel column as the host has it, and what the host does to it.
struct Panels {
  let column: PanelColumn
  let refresh: (Panel) -> Void
  let moveToTop: (PanelSlot) -> Void
  /// Removes the panel and its file.
  let remove: (Panel) -> Void
}
