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
    if let lesson = command as? ReadLesson {
      return try await courseLesson(lesson, answer: answer, legacyKey: request, reply: C.Reply.self)
    }
    switch answer {
    case .success(let body):
      let reply = try WireCodec.reply(C.Reply.self, from: body)
      if route.effect == .reads { await keep(body, C.name, request) }
      if let deletion = command as? DeleteCourse {
        await RemoteCourseCache.mark(deletion.course, missing: true, keep: keep)
      } else if command is RestoreDeletedCourse, let course = try WireCodec.decode(Course?.self, from: body) {
        await RemoteCourseCache.mark(course.id, missing: false, keep: keep)
      }
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
        continuation.yield(
          RemoteFollower<S>.missingCourse(request, in: folder, on: machine)
            ?? kept.flatMap(RemoteFollower<S>.decode) ?? .unavailable(.offline))
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

  private func courseLesson<Reply: Codable>(
    _ lesson: ReadLesson, answer: Result<Data, HostError>, legacyKey: Data, reply: Reply.Type
  ) async throws(HostError) -> Reply {
    let key = try WireCodec.encode(WatchLesson(course: lesson.course, lesson: lesson.lesson))
    switch answer {
    case .success(let body):
      let markdown = try WireCodec.decode(String?.self, from: body)
      await RemoteCourseCache.mark(lesson.course, missing: false, keep: keep)
      await keep(try WireCodec.encode(Feed<String?>.value(markdown)), WatchLesson.name, key)
      return try WireCodec.reply(reply, from: body)
    case .failure(.offline):
      if RemoteCourseCache.isMissing(lesson.course, in: folder, machine: machine) {
        throw .notFound(lesson.course.description)
      }
      if let body = folder.cached(WatchLesson.name, request: key, on: machine),
        let feed = RemoteFollower<WatchLesson>.decode(body)
      {
        switch feed {
        case .value(let markdown): return try WireCodec.reply(reply, from: WireCodec.encode(markdown))
        case .unavailable(let error): throw error
        }
      }
      guard let kept = folder.cached(ReadLesson.name, request: legacyKey, on: machine) else { throw .offline }
      return try WireCodec.reply(reply, from: kept)
    case .failure(let error):
      switch error {
      case .notFound, .invalidFile:
        await keep(try WireCodec.encode(Feed<String?>.unavailable(error)), WatchLesson.name, key)
      default: break
      }
      throw error
    }
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
    let kept =
      Self.missingCourse(request, in: folder, on: machine)
      ?? folder.cached(S.name, request: request, on: machine).flatMap(Self.decode)
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
      if S.name == WatchCourses.name || S.name == WatchCourse.name {
        await RemoteCourseCache.observe(
          body, as: S.name, request: request, previous: folder.cached(S.name, request: request, on: machine), keep: keep
        )
      }
      await keep(body, S.name, request)
      deliver(feed)
    }
  }

  static func missingCourse(_ request: Data, in folder: MachineFolder, on machine: MachineID) -> Feed<S.Value>? {
    guard S.name == WatchLesson.name, let lesson = try? WireCodec.decode(WatchLesson.self, from: request),
      RemoteCourseCache.isMissing(lesson.course, in: folder, machine: machine)
    else { return nil }
    return .unavailable(.notFound(lesson.course.description))
  }

  static func decode(_ body: Data) -> Feed<S.Value>? {
    try? JSONDecoder().decode(Feed<S.Value>.self, from: body)
  }
}

private enum RemoteCourseCache {
  static let missing = "course.missing"

  static func mark(_ course: EntityID, missing: Bool, keep: RemoteHost.Keep) async {
    await keep(Data([missing ? 1 : 0]), Self.missing, Data(course.description.utf8))
  }

  static func observe(
    _ body: Data, as name: String, request: Data, previous: Data?, keep: RemoteHost.Keep
  ) async {
    if name == WatchCourse.name, let watch = try? WireCodec.decode(WatchCourse.self, from: request),
      let feed = RemoteFollower<WatchCourse>.decode(body)
    {
      switch feed {
      case .value: await mark(watch.course, missing: false, keep: keep)
      case .unavailable(.notFound): await mark(watch.course, missing: true, keep: keep)
      case .unavailable: break
      }
    } else if name == WatchCourses.name, let old = previous.flatMap(RemoteFollower<WatchCourses>.decode),
      case .value(let before) = old, case .value(let now) = RemoteFollower<WatchCourses>.decode(body)
    {
      let previousIDs = Set(before.map(\.id))
      let currentIDs = Set(now.map(\.id))
      for course in previousIDs.subtracting(currentIDs) { await mark(course, missing: true, keep: keep) }
      for course in currentIDs.subtracting(previousIDs) { await mark(course, missing: false, keep: keep) }
    }
  }

  static func isMissing(_ course: EntityID, in folder: MachineFolder, machine: MachineID) -> Bool {
    folder.cached(missing, request: Data(course.description.utf8), on: machine) == Data([1])
  }
}
