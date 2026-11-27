import Foundation
import LociMedia
import LociModel
import LociStore

/// Keeps the follows and what reading them found. The fetching line asks it which follows are due and has it
/// look at each: a look reads only the newest episodes with GETs, and writes only when there is something new
/// or the reason it failed changed. Past episodes are listed when the person opens a follow page. Nothing here
/// takes an episode into the library, wakes the companion or notifies.
actor FollowKeeper {
  let store: Store
  let database: StoreDatabase
  let reader: any FollowReading
  let now: @Sendable () -> Timestamp
  let newID: @Sendable () -> EntityID
  let ytDlp: @Sendable () async -> YtDlp?
  let notify: @Sendable (Set<ContentChange>) async -> Void
  /// How often each follow is looked at.
  static let every: Int64 = 3_600_000

  init(
    store: Store, database: StoreDatabase, reader: any FollowReading, now: @escaping @Sendable () -> Timestamp,
    newID: @escaping @Sendable () -> EntityID, ytDlp: @escaping @Sendable () async -> YtDlp?,
    notify: @escaping @Sendable (Set<ContentChange>) async -> Void
  ) {
    self.store = store
    self.database = database
    self.reader = reader
    self.now = now
    self.newID = newID
    self.ytDlp = ytDlp
    self.notify = notify
  }

  /// The follows not looked at in the last hour, with when each last was; never looked at first.
  nonisolated func due(at now: Timestamp) -> [(follow: Follow, tried: Timestamp?)] {
    let states = (try? database.followStates()) ?? [:]
    return store.follows().compactMap { follow in
      let tried = states[follow.id]?.tried
      guard let tried, now.millisecondsSince1970 - tried.millisecondsSince1970 < Self.every else {
        return (follow, tried)
      }
      return nil
    }
  }

  /// Reads the follow's newest episodes and keeps the new ones, or why they could not be read.
  func look(_ follow: Follow) async {
    let found: Result<[Episode], FollowFailure>
    do throws(FollowFailure) {
      found = .success(try await reader.latest(follow.source))
    } catch {
      found = .failure(error)
    }
    guard let current = store.follows().first(where: { $0.id == follow.id }) else { return }
    if await keep(found, of: current, fresh: true, listed: false) { await notify([.follows]) }
  }

  /// Reads the follow's newest and past episodes; the past ones only once an hour unless asked `again`.
  func refresh(_ id: EntityID, again: Bool) async throws(HostError) {
    guard let follow = store.follows().first(where: { $0.id == id }) else { throw .notFound("follow \(id)") }
    let state = (try? database.followState(id)) ?? .init()
    let time = now()
    let listedLately = state.listed.map { time.millisecondsSince1970 - $0.millisecondsSince1970 < Self.every } ?? false
    var changed = false
    if again || state.problem != nil || !listedLately {
      let found: Result<[Episode], FollowFailure>
      do throws(FollowFailure) {
        found = .success(try await reader.past(follow, ytDlp: await ytDlp()))
      } catch {
        found = .failure(error)
      }
      changed = await keep(found, of: follow, fresh: false, listed: true)
    }
    if again || state.tried.map({ time.millisecondsSince1970 - $0.millisecondsSince1970 >= Self.every }) ?? true {
      let found: Result<[Episode], FollowFailure>
      do throws(FollowFailure) {
        found = .success(try await reader.latest(follow.source))
      } catch {
        found = .failure(error)
      }
      changed = await keep(found, of: follow, fresh: true, listed: false) || changed
    }
    if changed { await notify([.follows]) }
  }

  /// Whether what the person sees changed.
  private func keep(_ found: Result<[Episode], FollowFailure>, of follow: Follow, fresh: Bool, listed: Bool) async
    -> Bool
  {
    let time = now()
    guard store.follows().contains(where: { $0.id == follow.id }) else { return false }
    switch found {
    case .success(let episodes):
      let kept = (try? database.keepEpisodes(episodes, of: follow, at: time, fresh: fresh))?.changed ?? false
      let problem =
        (try? database.changeFollowState(follow.id) { state in
          if listed { state.listed = time } else { state.tried = time }
          state.problem = nil
        }) ?? false
      return kept || problem
    case .failure(let failure):
      return
        (try? database.changeFollowState(follow.id) { state in
          if listed { state.listed = time } else { state.tried = time }
          state.problem = failure.problem
        }) ?? false
    }
  }

  /// Who the link leads to, and the follow it already is.
  func preview(_ link: URL) async throws(HostError) -> FollowPreview {
    let preview = try await read(link)
    return preview.following(store.follows().first { $0.source.identity == preview.source.identity }?.id)
  }

  /// Follows what the link leads to; the follow it already is when it is one. What is out by now is not new.
  func start(_ link: URL) async throws(HostError) -> Follow {
    let preview = try await read(link)
    if let known = store.follows().first(where: { $0.source.identity == preview.source.identity }) { return known }
    let time = now()
    let follow = Follow(
      id: newID(), source: preview.source, name: preview.name, handle: preview.handle, picture: preview.picture,
      page: preview.page, followed: time)
    _ = try attempt { try store.changeFollows { $0.append(follow) } }
    _ = try? database.keepEpisodes(preview.episodes, of: follow, at: time, fresh: false)
    _ = try? database.changeFollowState(follow.id) { $0.tried = time }
    await notify([.follows])
    return follow
  }

  /// Stops following; the episodes kept and how reading them went are forgotten.
  func stop(_ id: EntityID) async throws(HostError) -> Follow {
    var stopped: Follow?
    _ = try attempt {
      try store.changeFollows { follows in
        stopped = follows.first { $0.id == id }
        follows.removeAll { $0.id == id }
      }
    }
    guard let stopped else { throw .notFound("follow \(id)") }
    try? database.forgetFollow(id)
    await notify([.follows])
    return stopped
  }

  /// Follows again what was stopped, as it was, and reads it at once.
  func restore(_ follow: Follow) async throws(HostError) {
    _ = try attempt {
      try store.changeFollows { follows in
        guard !follows.contains(where: { $0.id == follow.id || $0.source.identity == follow.source.identity }) else {
          return
        }
        follows.append(follow)
      }
    }
    await notify([.follows])
    await look(follow)
  }

  /// What came out until now is no longer new.
  func saw(_ id: EntityID) async throws(HostError) {
    let time = now()
    var found = false
    _ = try attempt {
      try store.changeFollows { follows in
        guard let index = follows.firstIndex(where: { $0.id == id }) else { return }
        found = true
        follows[index] = follows[index].opening(at: time)
      }
    }
    guard found else { throw .notFound("follow \(id)") }
    await notify([.follows])
  }

  private func read(_ link: URL) async throws(HostError) -> FollowPreview {
    guard let followable = FollowLink(link) else {
      throw .invalidRequest("\(link.absoluteString) is not a YouTube channel, a podcast show or a podcast feed")
    }
    do throws(FollowFailure) {
      return try await reader.preview(followable)
    } catch {
      throw .invalidRequest(Self.words(error))
    }
  }

  /// What went wrong, as `loci follow` says it.
  static func words(_ failure: FollowFailure) -> String {
    let what =
      switch failure.problem {
      case .signIn: "the site wants you signed in"
      case .gone: "the address no longer leads to a channel or show"
      case .refused: "the site refused this Mac"
      case .offline: "the site could not be reached"
      }
    return "Could not read it: \(what) (\(failure.reason))."
  }
}
