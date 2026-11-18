import Foundation
import LociModel
import LociRemote
import LociStore

/// Another Mac's host, over its link. Commands run concurrently on the connection of their lane.
/// Subscriptions get the whole value and then what changed, and follow the Mac across reconnections.
/// What was seen is kept, so the Mac's content can still be read while it is offline; writes then fail
/// with `HostError.offline`. A Mac that is not in the roster, or was removed, is offline for good.
public struct RemoteHost: LociModel.Host {
  let machine: MachineID
  private let folder: MachineFolder
  private let link: @Sendable () async -> PeerLink?
  private let keep: Keep

  /// Keeps a reply or a value under its name and request, if the Mac is still in the roster.
  typealias Keep = @Sendable (_ body: Data, _ name: String, _ request: Data) async -> Void

  init(
    machine: MachineID, folder: MachineFolder, link: @escaping @Sendable () async -> PeerLink?,
    keep: @escaping Keep
  ) {
    self.machine = machine
    self.folder = folder
    self.link = link
    self.keep = keep
  }

  public func run<C: Command>(_ command: C) async throws(HostError) -> C.Reply {
    guard let route = Wire.route(of: C.self) else {
      throw .invalidRequest("\(C.name) cannot be used on another Mac")
    }
    if let importing = command as? ImportMediaFile, importing.mode == .link {
      throw .invalidRequest("a file sent to another Mac can only be copied there")
    }
    let request = try WireCodec.encode(command)
    let answer = await link()?.session(for: route.lane)?.call(C.name, body: request) ?? .failure(.offline)
    switch answer {
    case .success(let body):
      let reply = try WireCodec.reply(C.Reply.self, from: body)
      if route.effect == .reads { await keep(body, C.name, request) }
      return reply
    case .failure(.offline) where route.effect == .reads:
      guard let kept = folder.cached(C.name, request: request, on: machine) else { throw .offline }
      return try WireCodec.reply(C.Reply.self, from: kept)
    case .failure(let error):
      throw error
    }
  }

  public func subscribe<S: Subscription>(_ subscription: S) -> AsyncStream<Feed<S.Value>> {
    let (feeds, continuation) = AsyncStream.makeStream(of: Feed<S.Value>.self)
    let following = Task { [link, keep, folder, machine] in
      guard let request = try? WireCodec.encode(subscription) else {
        continuation.yield(.unavailable(.invalidRequest("cannot encode \(S.name)")))
        continuation.finish()
        return
      }
      let kept = folder.cached(S.name, request: request, on: machine)
      guard let current = await link() else {
        continuation.yield(kept.flatMap(RemoteFollower<S>.decode) ?? .unavailable(.offline))
        continuation.finish()
        return
      }
      let follower = RemoteFollower<S>(
        request: request, machine: machine, folder: folder, link: current, keep: keep,
        deliver: { continuation.yield($0) })
      await follower.follow()
      continuation.finish()
    }
    continuation.onTermination = { _ in following.cancel() }
    return feeds
  }

  public func upload(_ file: LocalFile) async throws(HostError) -> Upload {
    guard let session = await link()?.session(for: .data) else { throw .offline }
    let pieces: AsyncThrowingStream<Data, any Error>
    do {
      pieces = try MachineFolder.pieces(of: file.url, size: 256 << 10)
    } catch {
      throw .storage(error.localizedDescription)
    }
    switch await session.upload(pieces, named: file.url.lastPathComponent) {
    case .success(let body): return try WireCodec.decode(Upload.self, from: body)
    case .failure(let error): throw error
    }
  }

  public func localFile(_ place: LocalPlace) async -> LocalFile? {
    nil
  }
}

/// One subscription on another Mac, across reconnections.
struct RemoteFollower<S: Subscription>: Sendable {
  let request: Data
  let machine: MachineID
  let folder: MachineFolder
  let link: PeerLink
  let keep: RemoteHost.Keep
  let deliver: @Sendable (Feed<S.Value>) -> Void

  func follow() async {
    let kept = folder.cached(S.name, request: request, on: machine).flatMap(Self.decode)
    if let kept { deliver(kept) }
    var shown = kept != nil
    while !Task.isCancelled {
      if await link.currentControl == nil, !shown {
        deliver(.unavailable(.offline))
        shown = true
      }
      guard let session = await link.nextControl() else { return }
      let (id, frames) = await session.subscribe(S.name, body: request)
      await withTaskCancellationHandler {
        await receive(frames, id: id, on: session)
      } onCancel: {
        Task { await session.unsubscribe(id) }
      }
      shown = true
    }
  }

  private func receive(_ frames: AsyncStream<FeedFrame>, id: UInt32, on session: CallerSession) async {
    var current: JSON?
    for await frame in frames {
      switch frame {
      case .whole(let json):
        current = json
      case .delta(let delta):
        guard let base = current, let next = try? delta.apply(to: base) else {
          current = nil
          await session.resend(id)
          continue
        }
        current = next
      case .refused(let error):
        deliver(.unavailable(error))
        return
      }
      guard let current, let body = try? current.data(), let feed = Self.decode(body) else { continue }
      await keep(body, S.name, request)
      deliver(feed)
    }
  }

  static func decode(_ body: Data) -> Feed<S.Value>? {
    try? JSONDecoder().decode(Feed<S.Value>.self, from: body)
  }
}
