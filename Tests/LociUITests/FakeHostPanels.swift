import LociModel

/// The panel column the test gave, served as the host serves it; changes to it are accepted and forgotten.
extension FakeHost {
  func panelColumn() async throws(HostError) -> PanelColumn { panels }

  func panels() async throws(HostError) -> [PanelEntry] {
    panels.slots.compactMap { slot in
      if case .panel(let panel) = slot { PanelEntry(name: panel.name, panel: panel) } else { nil }
    }
  }

  func savePanel(_ command: SavePanel) async throws(HostError) -> Done { Done() }
  func refreshPanel(_ command: RefreshPanel) async throws(HostError) -> Done { Done() }
  func movePanelToTop(_ command: MovePanelToTop) async throws(HostError) -> Done { Done() }
  func removePanel(_ command: RemovePanel) async throws(HostError) -> Done { Done() }
  func editPanel(_ command: EditPanel) async throws(HostError) -> Done { Done() }
  func markPanelLine(_ command: MarkPanelLine) async throws(HostError) -> Done { Done() }
}
