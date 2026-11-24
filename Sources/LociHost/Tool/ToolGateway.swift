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
  /// which run may still save; `AddFollowUp` is told the conversation it was set in.
  static let reading: [any Command.Type] = [
    Search.self, ListItems.self, ListPanels.self, ListTimers.self, CancelFollowUp.self, RemoveSchedule.self,
  ]
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
          return try WireCodec.encode(relative(folder.url, to: host.store.agentFolder))
        })
    }
  }

  /// Why a run's session may not make the call; `nil` when it may. A run that is over is held to what any run
  /// may do, and its panel saves are refused by the panels.
  static func refusal(of request: LocalCall.Request, in run: Run.ID, on host: LocalHost) async -> String? {
    let policy = await host.worker.policy(of: run) ?? .timers
    switch request {
    case .command(let name, _):
      return runCommands.contains(name) ? nil : policy.refusal(name)
    case .feeling: return policy == .review ? nil : policy.refusal("mood")
    case .upload: return policy.refusal("upload")
    case .follow, .itemFolder, .course: return nil
    }
  }

  /// What a run's session may run: what reads, setting follow-ups, and saving the panels it is for.
  static let runCommands: Set<String> = Set(
    ([Search.self, ListItems.self, ListPanels.self, ListTimers.self, CancelFollowUp.self] as [any Command.Type]).map {
      $0.name
    } + [ReadSource.name, FetchSourceRepository.name, AddFollowUp.name, SavePanel.name, EditPanel.name])

  private static func run(_ name: String, _ body: Data, for call: LocalCall, on host: LocalHost)
    async throws(HostError) -> Data
  {
    if name == AddFollowUp.name {
      let command = try WireCodec.decode(AddFollowUp.self, from: body)
      let set = AddFollowUp(command.time, command.what, in: call.session?.conversation)
      return try WireCodec.encode(try await host.addFollowUp(set))
    }
    if let command = Wire.toolCommands.first(where: { $0.name == name }) {
      return try await WireCodec.run(command, body: body, on: host)
    }
    let saver = Saver.loci(call.session?.conversation)
    switch name {
    case SavePanel.name:
      let panel = try WireCodec.decode(SavePanel.self, from: body).panel
      try await host.panels.save(panel, by: .loci, from: call.session)
      return try WireCodec.encode(Done())
    case EditPanel.name:
      let command = try WireCodec.decode(EditPanel.self, from: body)
      try await host.panels.edit(command.edit, of: command.panel, by: .loci, from: call.session)
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
    let feeds: AsyncStream<JSON>
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
