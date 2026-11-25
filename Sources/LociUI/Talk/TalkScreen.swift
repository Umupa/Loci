import LociModel
import SwiftUI

/// A home's conversation, the main one where the window opens or a project's, among lanes of panels laid out
/// as the person left them on this Mac. A link or a file dropped anywhere on it goes into the library.
struct TalkScreen: View {
  @Environment(\.openPage) private var openPage
  @Environment(\.peekLink) private var peekLink
  @Environment(\.host) private var host
  @Environment(\.locale) private var locale
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.changesAllowed) private var changesAllowed
  let home: Home
  /// The project's panels pinned to the chat, by name.
  var pinned: Set<String> = []
  let focusRequest: Int
  let attach: () -> Void
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  /// Whether the person left the panels showing.
  @Binding var columnPreferred: Bool
  @AppStorage private var storedLayout: Data
  @State private var draft: PassageDraft?
  @State private var newPanel: NewPanel?
  @State private var fill: ComposerFill?
  @State private var working = false
  /// The panel column, once the host has it; without it the conversation has the room to itself.
  @State private var panelColumn: Feed<PanelColumn>?

  /// The chat keeps its layout as it always did; each project keeps its own.
  init(
    home: Home, pinned: Set<String> = [], focusRequest: Int, attach: @escaping () -> Void,
    opened: @escaping (WindowState) -> Void, failed: @escaping (HostError) -> Void, columnPreferred: Binding<Bool>
  ) {
    self.home = home
    self.pinned = pinned
    self.focusRequest = focusRequest
    self.attach = attach
    self.opened = opened
    self.failed = failed
    _columnPreferred = columnPreferred
    _storedLayout = AppStorage(wrappedValue: Data(), TalkLayout.key + (home.project.map { " \($0)" } ?? ""))
  }

  var body: some View {
    TalkBoard(
      layout: layout, column: column, showsPanels: columnPreferred, building: building, making: newPanel == .asking,
      actions: actions
    ) {
      ConversationScreen(
        ref: home.conversation, draft: $draft, revealPassage: { if let page = Page($0.content) { openPage(page) } },
        attach: attach,
        focusRequest: focusRequest, panelRequest: panelRequest
      )
    }
    .padding(.top, Size.projectBarRoom)
    .padding(.horizontal, Spacing.m)
    .padding(.bottom, Spacing.s)
    .overlay(alignment: .topTrailing) {
      if column != nil {
        HStack(spacing: Spacing.xxs) {
          LayoutButton(layout: layout, panelsShown: $columnPreferred)
          PanelButton(title: .loci(columnPreferred ? "panels.hideColumn" : "panels.showColumn"), action: toggleColumn)
            .glassEffect(columnPreferred ? .identity : .regular, in: .capsule)
        }
        .padding(Spacing.s)
      }
    }
    .onChange(of: column?.panelNames) { settle() }
    .onChange(of: working) { settle() }
    .acceptingDrops()
    .environment(\.panelHome, home)
    .environment(\.pinnedPanels, pinned)
    .subscribing(WatchPanelColumn(of: home), into: $panelColumn)
  }

  /// The layout this Mac keeps, as JSON in its preferences; the standard one until the person changes it.
  private var layout: Binding<TalkLayout> {
    Binding(
      get: { (try? JSONDecoder().decode(TalkLayout.self, from: storedLayout)) ?? .standard },
      set: { storedLayout = (try? JSONEncoder().encode($0)) ?? storedLayout })
  }

  private var column: PanelColumn? { panelColumn?.value }

  /// What marks the skeleton of the panel being made, while one is.
  private var building: PanelSources? {
    if case .building(_, _, let sources) = newPanel { sources } else { nil }
  }

  private func toggleColumn() {
    withAnimation(reduceMotion ? nil : Motion.standard) { columnPreferred.toggle() }
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
      refresh: { panel in send(RefreshPanel(panel)) },
      moveToTop: { slot in
        withAnimation(reduceMotion ? nil : Motion.standard) {
          layout.wrappedValue = layout.wrappedValue.raising(slot.key)
        }
        send(MovePanelToTop(slot, in: home))
      },
      remove: { panel in send(RemovePanel(panel)) },
      edit: { command in await sent(command) },
      mark: { command in await sent(command) },
      pin: { panel, pinned in
        guard case .project(let id) = panel.home else { return }
        send(PinPanel(panel.name, of: id, pinned: pinned))
      })
  }

  /// Runs the command and says whether it worked, showing why when it did not.
  private func sent<C: Command>(_ command: C) async -> Bool {
    do throws(HostError) {
      _ = try await host.run(command)
      return true
    } catch {
      failed(error)
      return false
    }
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

  /// Says `words` in the home's conversation, as the person.
  private func ask(_ words: String) {
    guard changesAllowed else { return }
    Task {
      do throws(HostError) {
        _ = try await host.run(SendMessage(to: home.conversation, text: words, passage: nil))
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
