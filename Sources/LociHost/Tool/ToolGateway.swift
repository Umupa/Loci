import Foundation
import LociModel
import LociRemote
import LociStore
import os

/// Answers the `loci` command. Only the few commands and the one subscription it needs are open to it;
/// everything else in the Host protocol is refused.
enum ToolGateway {
  /// The commands that only read, run as any caller runs them. The three that put an item into the
  /// library, `AddLink`, `AddTextItem` and `ImportMediaFile`, are run as Loci's.
  static let reading: [any Command.Type] = [Search.self, ListItems.self]
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
    switch call.request {
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

  private static func run(_ name: String, _ body: Data, for call: LocalCall, on host: LocalHost)
    async throws(HostError) -> Data
  {
    let saver = Saver.loci(call.conversation)
    switch name {
    case AddLink.name:
      return try WireCodec.encode(try await host.addLink(try WireCodec.decode(AddLink.self, from: body), by: saver))
    case AddTextItem.name:
      let command = try WireCodec.decode(AddTextItem.self, from: body)
      return try WireCodec.encode(try await host.addTextItem(command, by: saver))
    case ImportMediaFile.name:
      let command = try WireCodec.decode(ImportMediaFile.self, from: body)
      return try WireCodec.encode(try await host.importMediaFile(command, by: saver))
    case _ where reading.contains(where: { $0.name == name }):
      return try await WireCodec.run(name, body: body, on: host)
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
