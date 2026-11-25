import Foundation
import LociModel
import LociStore

extension LocalHost {
  /// A home's column. The chat's also holds the panels projects pinned to it, where its order puts them.
  public func panelColumn(of home: Home) async throws(HostError) -> PanelColumn {
    let files = store.home(home)
    let panels = await self.panels.entries(of: home).compactMap(\.panel)
    let state = files.panelState()
    var marks = state.marks
    var pinned: [PanelPlace: Panel] = [:]
    if home == .chat {
      for project in store.projects() where !project.archived {
        let projectFiles = store.home(.project(project.id))
        let projectMarks = projectFiles.panelState().marks
        for name in project.pinned {
          guard let panel = projectFiles.panel(named: name)?.panel else { continue }
          pinned[.pinned(project.id, name)] = panel
          marks[PanelRef(name, in: .project(project.id)).key] = projectMarks[name]
        }
      }
    }
    let refreshing = await self.panels.refreshing.compactMap { ref -> String? in
      if ref.home == home { return ref.name }
      guard case .project(let id) = ref.home, pinned[.pinned(id, ref.name)] != nil else { return nil }
      return ref.key
    }
    return PanelColumn(
      slots: PanelOrder.slots(state.order, panels: panels, pinned: pinned, reading: home == .chat ? readingNow() : []),
      refreshing: Set(refreshing), marks: marks, readings: readings(of: panels, in: home, pinned: pinned))
  }

  public func panels(of home: Home) async throws(HostError) -> [PanelEntry] {
    await panels.entries(of: home)
  }

  /// Checked here as well as in `loci panel save`, so no caller writes a panel that cannot be shown. The
  /// person's own save is kept as it is.
  public func savePanel(_ command: SavePanel) async throws(HostError) -> Done {
    try await panels.save(command.panel, in: command.home, by: .you, from: nil)
    return Done()
  }

  public func editPanel(_ command: EditPanel) async throws(HostError) -> Done {
    try await panels.edit(command.edit, of: command.ref, by: .you, from: nil)
    return Done()
  }

  public func markPanelLine(_ command: MarkPanelLine) async throws(HostError) -> Done {
    try await panels.mark(command)
    return Done()
  }

  public func refreshPanel(_ command: RefreshPanel) async throws(HostError) -> Done {
    try await panels.refreshSoon(command.ref)
    return Done()
  }

  public func movePanelToTop(_ command: MovePanelToTop) async throws(HostError) -> Done {
    let files = store.home(command.home)
    let names = files.panels().map(\.name)
    let pinned = command.home == .chat ? pinnedPlaces() : []
    switch command.place {
    case .panel(let name) where !names.contains(name): throw .notFound(name)
    case .pinned(_, let name) where !pinned.contains(command.place): throw .notFound(name)
    default: break
    }
    try attempt {
      _ = try files.changePanelState { state in
        state.order = PanelOrder.movingToTop(command.place, in: state.order, panels: names, pinned: pinned)
      }
    }
    await follow([.loci(.panels)])
    return Done()
  }

  public func removePanel(_ command: RemovePanel) async throws(HostError) -> Done {
    try await panels.remove(command.ref)
    return Done()
  }

  /// The places of the panels pinned to the chat, by project.
  func pinnedPlaces() -> [PanelPlace] {
    store.projects().filter { !$0.archived }.flatMap { project in
      project.pinned.map { PanelPlace.pinned(project.id, $0) }
    }
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
