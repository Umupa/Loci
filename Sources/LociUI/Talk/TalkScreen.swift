import LociModel
import SwiftUI

/// The main conversation with Loci, where the window opens, with the panel column on its right. A link or a
/// file dropped anywhere on it goes into the library.
struct TalkScreen: View {
  @Environment(\.openPage) private var openPage
  @Environment(\.peekLink) private var peekLink
  @Environment(\.host) private var host
  @Environment(\.locale) private var locale
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.changesAllowed) private var changesAllowed
  let focusRequest: Int
  let attach: () -> Void
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  /// Whether the person left the panel column showing.
  @Binding var columnPreferred: Bool
  @State private var draft: PassageDraft?
  @State private var newPanel: NewPanel?
  @State private var fill: ComposerFill?
  @State private var working = false
  @State private var fit = PaneFit.panelColumn
  /// The panel column, once the host has it; without it the conversation has the room to itself.
  @State private var panelColumn: Feed<PanelColumn>?

  var body: some View {
    HStack(spacing: 0) {
      ConversationScreen(
        ref: .main, draft: $draft, revealPassage: { if let page = Page($0.content) { openPage(page) } }, attach: attach,
        focusRequest: focusRequest, panelRequest: panelRequest
      )
      if let column, fit.shows(columnPreferred) {
        PanelColumnView(column: column, building: building, making: newPanel == .asking, actions: actions)
          .frame(width: Size.panelColumn)
          .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
      }
    }
    .overlay(alignment: .topTrailing) {
      if column != nil {
        let shown = fit.shows(columnPreferred)
        PanelButton(title: .loci(shown ? "panels.hideColumn" : "panels.showColumn"), action: toggleColumn)
          .glassEffect(shown ? .identity : .regular, in: .capsule)
          .padding(Spacing.s)
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
    .onChange(of: column?.panelNames) { settle() }
    .onChange(of: working) { settle() }
    .acceptingDrops()
    .subscribing(WatchPanelColumn(), into: $panelColumn)
  }

  private var column: PanelColumn? { panelColumn?.value }

  /// What marks the skeleton of the panel being made, while one is.
  private var building: PanelSources? {
    if case .building(_, _, let sources) = newPanel { sources } else { nil }
  }

  private func toggleColumn() {
    withAnimation(reduceMotion ? nil : Motion.fold) { columnPreferred = fit.toggle(columnPreferred) }
  }

  private func settle() {
    newPanel = newPanel?.settled(names: column?.panelNames ?? [], working: working)
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
          known: column?.panelNames ?? [], started: working,
          sources: PanelSources.named(in: typed, locale: locale))
      },
      fill: fill,
      working: { working = $0 })
  }

  private var actions: PanelActions {
    PanelActions(
      open: open, openItem: { openPage(.item($0)) },
      ask: ask,
      create: { newPanel = .asking },
      revise: { panel in fill = .revising(panel, serial: (fill?.serial ?? 0) + 1, locale: locale) },
      refresh: { panel in send(RefreshPanel(panel.name)) }, moveToTop: { send(MovePanelToTop($0)) },
      remove: { panel in send(RemovePanel(panel.name)) })
  }

  private func send<C: Command>(_ command: C) {
    Task {
      do throws(HostError) {
        _ = try await host.run(command)
      } catch {
        failed(error)
      }
    }
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

  /// A web page opens over the window; a `loci://` place opens that item.
  private func open(_ url: URL) {
    if let locator = Locator(url.absoluteString), let page = Page(locator.content) {
      openPage(page)
    } else if url.isWebLink {
      peekLink?(url)
    }
  }
}
