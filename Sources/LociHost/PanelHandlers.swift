import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func panelColumn() async throws(HostError) -> PanelColumn {
    let panels = await self.panels.entries().compactMap(\.panel)
    let state = store.panelState()
    return PanelColumn(
      slots: PanelOrder.slots(state.order, panels: panels, reading: readingNow()),
      refreshing: await self.panels.refreshingNames, marks: state.marks)
  }

  public func panels() async throws(HostError) -> [PanelEntry] {
    await panels.entries()
  }

  /// Checked here as well as in `loci panel save`, so no caller writes a panel that cannot be shown. The
  /// person's own save is kept as it is.
  public func savePanel(_ command: SavePanel) async throws(HostError) -> Done {
    try await panels.save(command.panel, by: .you, from: nil)
    return Done()
  }

  public func editPanel(_ command: EditPanel) async throws(HostError) -> Done {
    try await panels.edit(command.edit, of: command.panel, by: .you, from: nil)
    return Done()
  }

  public func markPanelLine(_ command: MarkPanelLine) async throws(HostError) -> Done {
    try await panels.mark(command)
    return Done()
  }

  public func refreshPanel(_ command: RefreshPanel) async throws(HostError) -> Done {
    try await panels.refreshSoon(command.panel)
    return Done()
  }

  public func movePanelToTop(_ command: MovePanelToTop) async throws(HostError) -> Done {
    let names = store.panels().map(\.name)
    if case .panel(let name) = command.place, !names.contains(name) { throw .notFound(name) }
    try attempt {
      _ = try store.changePanelState { state in
        state.order = PanelOrder.movingToTop(command.place, in: state.order, panels: names)
      }
    }
    await follow([.loci(.panels)])
    return Done()
  }

  public func removePanel(_ command: RemovePanel) async throws(HostError) -> Done {
    try await panels.remove(command.panel)
    return Done()
  }

  /// Items read partway, most recently read first, leaving out what cannot be told how far along it is.
  private func readingNow() -> [ReadingNow] {
    let partway = ((try? database.readingPartway()) ?? []).compactMap { entry -> (id: EntityID, position: Locator?)? in
      switch entry.content {
      case .item(let id): (id: id, position: entry.state.position)
      case .lesson: nil
      }
    }
    let items = store.items(withIDs: Set(partway.map(\.id)))
    return partway.compactMap { entry in
      guard let item = items[entry.id], let position = entry.position else { return nil }
      return ReadingProgress.of(position, in: item) { try? store.content(of: entry.id) }
    }
  }
}
