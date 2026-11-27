import Foundation
import LociModel
import LociRemote
import LociStore
import os

/// Answers the `loci` command. Only the few commands and the one subscription it needs are open to it;
/// everything else in the Host protocol is refused. A run in the background may do less: see `RunPolicy`.
enum ToolGateway {
  /// The commands run as any caller runs them. The three that put an item into the library, `AddLink`,
  /// `AddTextItem` and `ImportMediaFile`, are run as Loci's; `SavePanel` goes through the panels, which know
  /// which run may still save; `AddFollowUp` is told the conversation it was set in; listing and changing
  /// timers sees only the session's own home (`runTimer`).
  static let reading: [any Command.Type] = [Search.self, ListItems.self, ListPanels.self]
  static let subscriptions: [any Subscription.Type] = [ItemJob.self]

  private static let log = Logger(subsystem: "com.loci.native.dev", category: "tool")

  /// Answers calls at `socket` until the calling task is cancelled.
  static func serve(_ host: LocalHost, at socket: URL) async {
    do {
      try SocketFolder.prepare(for: socket)
      try await LocalSocket.serve(at: socket) { call, reply in
        await answer(call, on: host, reply: reply)
      }
    } catch {
      log.error("the loci command cannot reach the app: \(String(describing: error), privacy: .public)")
    }
  }

  static func answer(
    _ call: LocalCall, on host: LocalHost, reply: @Sendable (LocalReply) async throws -> Void
  ) async {
    if case .run(let run)? = call.session, let refusal = await refusal(of: call.request, in: run, on: host) {
      try? await reply(.failed(.invalidRequest(refusal)))
      return
    }
    switch call.request {
    case .course(let request):
      try? await reply(
        await once { () async throws(HostError) in
          try await runCourse(request, from: call.session, on: host)
        })
    case .feeling(let request):
      try? await reply(
        await once { () async throws(HostError) in
          try WireCodec.encode(try await host.loci.context.feelings.run(request, in: call.session?.conversation))
        })
    case .command(let name, let body):
      try? await reply(await once { () async throws(HostError) in try await run(name, body, for: call, on: host) })
    case .follow(let name, let body):
      await follow(name, body, on: host, reply: reply)
    case .upload(let path):
      try? await reply(
        await once { () async throws(HostError) in
          try WireCodec.encode(try await host.upload(LocalFile(URL(filePath: path))))
        })
    case .itemFolder(let item):
      try? await reply(
        await once { () async throws(HostError) in
          guard let folder = await host.localFile(.item(item)) else { throw .notFound(item.description) }
          let home = await home(of: call.session, on: host)
          return try WireCodec.encode(relative(folder.url, to: host.store.home(home).folder))
        })
    }
  }

  /// Why a run's session may not make the call; `nil` when it may. A run that is over, or waits to be tried
  /// again, may do nothing, so what its session still sends never lands anywhere; one stopped under way is held
  /// to what any run may do, and its panel saves are refused by the panels.
  static func refusal(of request: LocalCall.Request, in run: Run.ID, on host: LocalHost) async -> String? {
    if await host.worker.isClosed(run) { return Self.stopped }
    let access = await host.worker.access(of: run)
    if access == nil, await host.worker.home(of: run) == nil, (try? host.database.run(run)) != nil {
      return Self.over
    }
    let policy = access?.policy ?? .timers
    switch request {
    case .command(let name, let body) where policy == .repair:
      guard repairCommands.contains(name), let grant = access?.repair else { return policy.refusal(name) }
      let named =
        switch name {
        case SaveDataSource.name: (try? WireCodec.decode(SaveDataSource.self, from: body))?.source.name
        case TestDataSource.name: (try? WireCodec.decode(TestDataSource.self, from: body))?.source
        default: grant.source.name
        }
      return named == grant.source.name ? nil : "This repair mends only the source \(grant.source.name); use that one."
    case .command(let name, _):
      if name == AddNextUp.name, policy == .review { return policy.refusal("next add") }
      return runCommands.contains(name) ? nil : policy.refusal(name)
    case .feeling: return policy == .review ? nil : policy.refusal("mood")
    case .upload: return policy.refusal("upload")
    case .follow, .itemFolder, .course: return nil
    }
  }

  static let stopped = "This run's project was archived, deleted or kept out of memory; loci does nothing more for it."
  static let over = "This run is over; loci does nothing more for it."

  /// What a run's session may run: what reads, setting follow-ups, saving the panels it is for, and putting a
  /// card on the deck (not in the daily review).
  static let runCommands: Set<String> = Set(
    ([Search.self, ListItems.self, ListPanels.self, ListTimers.self, CancelFollowUp.self] as [any Command.Type]).map {
      $0.name
    } + [
      ReadSource.name, FetchSourceRepository.name, AddFollowUp.name, SavePanel.name, EditPanel.name,
      PickPanelEntries.name,
      ListConnectors.name, CallConnector.name, Recall.name, DescribeProject.name, AddNextUp.name,
    ])

  /// What a repair's session may run: show, test and save sources.
  static let repairCommands: Set<String> = [ListDataSources.name, TestDataSource.name, SaveDataSource.name]

  /// The repair the run under way may save under; refused once the run is over or is no repair.
  private static func grant(of run: Run.ID, _ host: LocalHost) async throws(HostError) -> RepairGrant {
    guard let grant = await host.worker.access(of: run)?.repair else {
      throw .invalidRequest("This run may not change sources: only a repair under way may save the source it mends.")
    }
    return grant
  }

  /// The home a session works in: a project's conversation and runs are the project's, everything else the chat's.
  /// The event the run's session works on, which what it sets descends from; `nil` outside a run.
  static func event(of session: LocalSession?, on host: LocalHost) async throws(HostError) -> Event? {
    guard case .run(let run)? = session else { return nil }
    guard let event = await host.worker.access(of: run)?.event else { throw .invalidRequest(over) }
    return event
  }

  static func home(of session: LocalSession?, on host: LocalHost) async -> Home {
    switch session {
    case .conversation(let conversation): conversation.home
    case .run(let run): await host.worker.home(of: run) ?? .chat
    case .course, nil: .chat
    }
  }

  private static func run(_ name: String, _ body: Data, for call: LocalCall, on host: LocalHost)
    async throws(HostError) -> Data
  {
    if name == ReadSource.name {
      let command = try WireCodec.decode(ReadSource.self, from: body)
      if let caller = call.session?.caller, let site = await host.connectorKeeper.signedInSite(for: command.url) {
        return try WireCodec.encode(try await host.connectorKeeper.readSite(command.url, record: site, by: caller))
      }
      if case .run? = call.session {
        return try WireCodec.encode(try await host.sources.read(command.url, fresh: true))
      }
    }
    if name == CallConnector.name {
      let command = try WireCodec.decode(CallConnector.self, from: body)
      return try WireCodec.encode(try await host.callConnector(command, from: call.session?.caller))
    }
    if name == ListConnectors.name {
      await host.connectorKeeper.refreshAll()
      return try WireCodec.encode(try await host.connectors().connected)
    }
    let home = await home(of: call.session, on: host)
    if name == AddFollowUp.name {
      let command = try WireCodec.decode(AddFollowUp.self, from: body)
      let place = call.session?.conversation ?? (home == .chat ? nil : home.conversation)
      return try WireCodec.encode(
        try await host.addFollowUp(
          AddFollowUp(command.time, command.what, in: place, deadline: command.deadline),
          parent: try await event(of: call.session, on: host)))
    }
    if name == AddSchedule.name {
      let command = try WireCodec.decode(AddSchedule.self, from: body)
      return try WireCodec.encode(
        try await host.addSchedule(AddSchedule(command.scheduleName, command.draft, in: home)))
    }
    if name == Recall.name {
      return try WireCodec.encode(try await host.recall(try WireCodec.decode(Recall.self, from: body), from: home))
    }
    if name == ListPanels.name {
      return try WireCodec.encode(try await host.panels(of: home))
    }
    if name == SaveDataSource.name {
      let command = try WireCodec.decode(SaveDataSource.self, from: body)
      if case .run(let run) = call.session {
        return try WireCodec.encode(
          try await host.saveDataSource(command.source, repairing: try await grant(of: run, host)))
      }
      return try WireCodec.encode(try await host.saveDataSource(SaveDataSource(command.source, in: home)))
    }
    if name == TestDataSource.name {
      let command = try WireCodec.decode(TestDataSource.self, from: body)
      let place = if case .run(let run) = call.session { try await grant(of: run, host).source.home } else { home }
      return try WireCodec.encode(
        try await host.testDataSource(TestDataSource(command.source, script: command.script, in: place)))
    }
    if name == PickPanelEntries.name {
      let command = try WireCodec.decode(PickPanelEntries.self, from: body)
      try await host.panels.pick(command, in: home, from: call.session)
      return try WireCodec.encode(Done())
    }
    if name == ListDataSources.name {
      let repair: RepairGrant? =
        if case .run(let run) = call.session { await host.worker.access(of: run)?.repair } else { nil }
      return try WireCodec.encode(try await host.dataSources(of: home, named: repair?.source.name))
    }
    if name == NameProject.name || name == IconProject.name || name == DescribeProject.name {
      guard case .project(let project) = home else { throw .invalidRequest(NameProject.outside) }
      if name == NameProject.name {
        let command = try WireCodec.decode(NameProject.self, from: body)
        let existingIcon = (try? host.store.project(project))?.icon
        let renamed = try await host.renameProject(RenameProject(project, to: command.newName))
        guard let icon = command.icon, existingIcon == nil else { return try WireCodec.encode(renamed) }
        return try WireCodec.encode(try await host.setProjectIcon(SetProjectIcon(project, icon: icon)))
      }
      if name == IconProject.name {
        let command = try WireCodec.decode(IconProject.self, from: body)
        return try WireCodec.encode(try await host.setProjectIcon(SetProjectIcon(project, icon: command.icon)))
      }
      let command = try WireCodec.decode(DescribeProject.self, from: body)
      return try WireCodec.encode(try await host.describeProject(DescribeProject(command.summary, of: project)))
    }
    if name == AddNextUp.name || name == ProposeApproval.name,
      let reply = try await runNextUp(name, body, in: home, from: try await event(of: call.session, on: host), on: host)
    {
      return reply
    }
    if let reply = try await runTimer(name, body, in: home, on: host) { return reply }
    if let command = Wire.toolCommands.first(where: { $0.name == name }) {
      return try await WireCodec.run(command, body: body, on: host)
    }
    let saver = Saver.loci(call.session?.conversation)
    switch name {
    case SavePanel.name:
      let panel = try WireCodec.decode(SavePanel.self, from: body).panel
      try await host.panels.save(panel, in: home, by: .loci, from: call.session)
      return try WireCodec.encode(Done())
    case EditPanel.name:
      let command = try WireCodec.decode(EditPanel.self, from: body)
      try await host.panels.edit(command.edit, of: PanelRef(command.panel, in: home), by: .loci, from: call.session)
      return try WireCodec.encode(Done())
    case _ where reading.contains(where: { $0.name == name }):
      return try await WireCodec.run(name, body: body, on: host)
    case AddLink.name:
      return try WireCodec.encode(try await host.addLink(try WireCodec.decode(AddLink.self, from: body), by: saver))
    case AddTextItem.name:
      let command = try WireCodec.decode(AddTextItem.self, from: body)
      return try WireCodec.encode(try await host.addTextItem(command, by: saver))
    case ImportMediaFile.name:
      let command = try WireCodec.decode(ImportMediaFile.self, from: body)
      return try WireCodec.encode(try await host.importMediaFile(command, by: saver))
    default:
      throw .invalidRequest("loci cannot run \(name)")
    }
  }

  /// Sends each feed until the caller hangs up.
  private static func follow(
    _ name: String, _ body: Data, on host: LocalHost, reply: @Sendable (LocalReply) async throws -> Void
  ) async {
    guard subscriptions.contains(where: { $0.name == name }) else {
      try? await reply(.failed(.invalidRequest("loci cannot follow \(name)")))
      return
    }
    let feeds: AsyncStream<JSONValue>
    do throws(HostError) {
      feeds = try WireCodec.feeds(name, body: body, on: host)
    } catch {
      try? await reply(.failed(error))
      return
    }
    for await feed in feeds {
      guard let data = try? feed.data() else { continue }
      do {
        try await reply(.value(data))
      } catch {
        return
      }
    }
  }

  private static func once(_ body: () async throws(HostError) -> Data) async -> LocalReply {
    do throws(HostError) {
      return .value(try await body())
    } catch {
      return .failed(error)
    }
  }

  /// `../library/<folder>/` for an item's folder, as Loci sees it from its `agent` folder.
  static func relative(_ folder: URL, to agentFolder: URL) -> String {
    let from = agentFolder.standardizedFileURL.pathComponents
    let to = folder.standardizedFileURL.pathComponents
    let shared = zip(from, to).prefix { $0 == $1 }.count
    let path = Array(repeating: "..", count: from.count - shared) + to.dropFirst(shared)
    return path.joined(separator: "/") + "/"
  }
}

extension LocalSession {
  /// Who a connector call is recorded as made by.
  var caller: ConnectorCall.Caller {
    switch self {
    case .conversation(let conversation): .conversation(conversation)
    case .course(let course, _): .conversation(.course(course))
    case .run(let run): .run(run)
    }
  }
}
