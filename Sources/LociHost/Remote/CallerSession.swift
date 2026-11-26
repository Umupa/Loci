import Foundation
import LociModel
import LociRemote
import LociStore

/// What a subscription receives on the wire.
enum FeedFrame: Sendable {
  case whole(JSONValue)
  case delta(JSONDelta)
  case refused(HostError)
}

/// This Mac's end of one connection to another Mac: calls wait for their replies by id, subscriptions get
/// their frames, and everything still waiting fails with `offline` when the connection ends.
actor CallerSession {
  private let channel: SecureChannel
  private let unpaired: @Sendable () async -> Void
  private var nextID: UInt32 = 0
  private var pending: [UInt32: CheckedContinuation<Result<Data, HostError>, Never>] = [:]
  private var feeds: [UInt32: AsyncStream<FeedFrame>.Continuation] = [:]
  private var isEnded = false
  private var endWaiters: [UInt64: CheckedContinuation<Void, Never>] = [:]
  private var waiterSerial: UInt64 = 0

  /// `unpaired` runs when the other Mac says it removed this one.
  init(channel: SecureChannel, unpaired: @escaping @Sendable () async -> Void) {
    self.channel = channel
    self.unpaired = unpaired
  }

  func start() {
    Task { await self.read() }
  }

  /// Returns once the connection has ended, or the task waiting for it is cancelled.
  func ended() async {
    guard !isEnded, !Task.isCancelled else { return }
    waiterSerial += 1
    let waiter = waiterSerial
    await withTaskCancellationHandler {
      await withCheckedContinuation { endWaiters[waiter] = $0 }
    } onCancel: {
      Task { await self.stopWaiting(waiter) }
    }
  }

  private func stopWaiting(_ waiter: UInt64) {
    endWaiters.removeValue(forKey: waiter)?.resume()
  }

  /// How many are waiting for the connection to end.
  var waitingForEnd: Int { endWaiters.count }

  /// A call, an upload or a subscription is still waiting on this connection.
  var isBusy: Bool { !pending.isEmpty || !feeds.isEmpty }

  func close() async {
    await channel.close()
  }

  func send(_ frame: Frame) async {
    try? await channel.send(frame.encoded)
  }

  func call(_ name: String, body: Data) async -> Result<Data, HostError> {
    guard !isEnded else { return .failure(.offline) }
    let id = allocate()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        pending[id] = continuation
        Task { await self.sendOrFail(.call(id: id, name: name, body: body), id: id) }
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }

  /// Sends a file in pieces and returns the host's name for it.
  func upload(_ pieces: AsyncThrowingStream<Data, any Error>, named name: String) async -> Result<Data, HostError> {
    guard !isEnded else { return .failure(.offline) }
    let id = allocate()
    return await withCheckedContinuation { continuation in
      pending[id] = continuation
      Task { await self.stream(pieces, named: name, id: id) }
    }
  }

  func subscribe(_ name: String, body: Data) -> (UInt32, AsyncStream<FeedFrame>) {
    let id = allocate()
    let (frames, continuation) = AsyncStream.makeStream(of: FeedFrame.self)
    if isEnded {
      continuation.finish()
    } else {
      feeds[id] = continuation
      Task { await self.send(.subscribe(id: id, name: name, body: body)) }
    }
    return (id, frames)
  }

  func unsubscribe(_ id: UInt32) async {
    guard feeds.removeValue(forKey: id) != nil else { return }
    await send(.unsubscribe(id: id))
  }

  private func allocate() -> UInt32 {
    nextID &+= 1
    return nextID
  }

  private func cancel(_ id: UInt32) async {
    guard let waiting = pending.removeValue(forKey: id) else { return }
    waiting.resume(returning: .failure(.offline))
    await send(.cancel(id: id))
  }

  private func sendOrFail(_ frame: Frame, id: UInt32) async {
    do {
      try await channel.send(frame.encoded)
    } catch {
      pending.removeValue(forKey: id)?.resume(returning: .failure(.offline))
    }
  }

  private func stream(_ pieces: AsyncThrowingStream<Data, any Error>, named name: String, id: UInt32) async {
    do {
      for try await piece in pieces { try await channel.send(Frame.uploadPart(id: id, bytes: piece).encoded) }
      try await channel.send(Frame.uploadEnd(id: id, fileName: name).encoded)
    } catch is ChannelError {
      pending.removeValue(forKey: id)?.resume(returning: .failure(.offline))
    } catch {
      pending.removeValue(forKey: id)?.resume(returning: .failure(.storage(error.localizedDescription)))
    }
  }

  private func read() async {
    while let message = try? await channel.receive() {
      guard let frame = Frame(message) else { continue }
      await handle(frame)
    }
    isEnded = true
    for waiting in pending.values { waiting.resume(returning: .failure(.offline)) }
    pending = [:]
    for feed in feeds.values { feed.finish() }
    feeds = [:]
    for waiter in endWaiters.values { waiter.resume() }
    endWaiters = [:]
  }

  private func handle(_ frame: Frame) async {
    switch frame {
    case .reply(let id, let body):
      pending.removeValue(forKey: id)?.resume(returning: .success(body))
    case .failure(let id, let error):
      if let waiting = pending.removeValue(forKey: id) {
        waiting.resume(returning: .failure(error))
      } else {
        feeds.removeValue(forKey: id).map {
          $0.yield(.refused(error))
          $0.finish()
        }
      }
    case .feed(let id, let body):
      guard let json = try? JSONDecoder().decode(JSONValue.self, from: body) else { return }
      feeds[id]?.yield(.whole(json))
    case .delta(let id, let body):
      guard let delta = try? JSONDecoder().decode(JSONDelta.self, from: body) else { return }
      feeds[id]?.yield(.delta(delta))
    case .unpaired:
      await unpaired()
    case .call, .cancel, .subscribe, .unsubscribe, .resend, .uploadPart, .uploadEnd:
      return
    }
  }

  func resend(_ id: UInt32) async {
    await send(.resend(id: id))
  }
}
