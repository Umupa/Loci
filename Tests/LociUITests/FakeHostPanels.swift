import LociModel

/// The panel columns the test gave, served as the host serves them; changes to them are accepted and forgotten.
extension FakeHost {
  func panelColumn(of home: Home) async throws(HostError) -> PanelColumn {
    switch home {
    case .chat: panels
    case .project(let id): projectPanels[id] ?? PanelColumn(slots: [])
    }
  }

  func panels(of home: Home) async throws(HostError) -> [PanelEntry] {
    try await panelColumn(of: home).slots.compactMap { slot in
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

/// The project bar the test gave; what is asked of it is accepted and forgotten.
extension FakeHost {
  func projectBar() async throws(HostError) -> ProjectBar { projects }

  func startProject(_ command: StartProject) async throws(HostError) -> Project {
    var entropy = SystemRandomNumberGenerator()
    return Project(id: EntityID(at: .now, entropy: &entropy), name: nil, createdAt: Timestamp(.now))
  }

  func renameProject(_ command: RenameProject) async throws(HostError) -> Project { try project(command.project) }
  func describeProject(_ command: DescribeProject) async throws(HostError) -> Project {
    guard let id = command.project else { throw .invalidRequest(NameProject.outside) }
    return try project(id)
  }
  func setProjectRemembered(_ command: SetProjectRemembered) async throws(HostError) -> Done { Done() }
  func archiveProject(_ command: ArchiveProject) async throws(HostError) -> Done { Done() }
  func deleteProject(_ command: DeleteProject) async throws(HostError) -> Done { Done() }
  func restoreDeletedProject() async throws(HostError) -> Project? { nil }
  func seeProject(_ command: SeeProject) async throws(HostError) -> Done { Done() }
  func pinPanel(_ command: PinPanel) async throws(HostError) -> Done { Done() }

  private func project(_ id: Project.ID) throws(HostError) -> Project {
    guard let found = (projects.projects + projects.archived).first(where: { $0.id == id }) else {
      throw .notFound(id.description)
    }
    return found
  }
}

/// Sources as the column's readings hold them; saving and testing one is accepted and forgotten.
extension FakeHost {
  func saveDataSource(_ command: SaveDataSource) async throws(HostError) -> SourceOutcome { .records([:]) }
  func testDataSource(_ command: TestDataSource) async throws(HostError) -> [SourceReplay] { [] }
  func dataSources(of home: Home) async throws(HostError) -> [DataSourceEntry] { [] }

  func sourceHistory(_ subscription: WatchSourceHistory) async throws(HostError) -> SourceHistory? {
    switch (panels.readings.snapshots[subscription.source]?.value(subscription.field), subscription.range) {
    case (.points(let points), let range?): .points(SourceHistory.cut(points, to: range))
    case (.candles(let candles), _): .candles(candles)
    default: nil
    }
  }
}
