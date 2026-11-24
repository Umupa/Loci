import Foundation
import LociModel
import LociRemote
import LociStore

/// One paired Mac's connection to this one, as served: each call runs on its own, each subscription sends
/// its whole value once and then only what changed.
actor GatewaySession {
  let peer: MachineID
  private let channel: SecureChannel
  private let host: any LociModel.Host
  private let folder: MachineFolder
  private let newID: @Sendable () -> EntityID
  private let unpaired: @Sendable (MachineID) async -> Void
  private var calls: [UInt32: Task<Void, Never>] = [:]
  private var subscriptions: [UInt32: Task<Void, Never>] = [:]
  private var lastSent: [UInt32: JSONValue] = [:]
  private var uploads: [UInt32: IncomingUpload] = [:]

  init(
    peer: MachineID, channel: SecureChannel, host: any LociModel.Host, folder: MachineFolder,
    newID: @escaping @Sendable () -> EntityID, unpaired: @escaping @Sendable (MachineID) async -> Void
  ) {
    self.peer = peer
    self.unpaired = unpaired
    self.channel = channel
    self.host = host
    self.folder = folder
    self.newID = newID
  }

  /// Serves until the connection ends, then stops everything it started.
  func serve() async {
    while let message = try? await channel.receive() {
      guard let frame = Frame(message) else { continue }
      await handle(frame)
    }
    for task in calls.values { task.cancel() }
    for task in subscriptions.values { task.cancel() }
    for upload in uploads.values { upload.abandon() }
    calls = [:]
    subscriptions = [:]
    uploads = [:]
  }

  /// Tells the Mac it was removed, and hangs up.
  func unpair() async {
    try? await channel.send(Frame.unpaired.encoded)
    await channel.close()
  }

  private func handle(_ frame: Frame) async {
    switch frame {
    case .call(let id, let name, let body):
      let host = host
      calls[id] = Task {
        let answer: Frame
        do throws(HostError) {
          answer = .reply(id: id, body: try await WireCodec.run(name, body: body, on: host))
        } catch {
          answer = .failure(id: id, error)
        }
        await self.finish(id, with: answer)
      }
    case .cancel(let id):
      calls.removeValue(forKey: id)?.cancel()
    case .subscribe(let id, let name, let body):
      do throws(HostError) {
        let feeds = try WireCodec.feeds(name, body: body, on: host)
        subscriptions[id] = Task {
          for await json in feeds { await self.deliver(json, on: id) }
        }
      } catch {
        await send(.failure(id: id, error))
      }
    case .unsubscribe(let id):
      subscriptions.removeValue(forKey: id)?.cancel()
      lastSent[id] = nil
    case .resend(let id):
      if let json = lastSent[id], let body = try? json.data() { await send(.feed(id: id, body: body)) }
    case .uploadPart(let id, let bytes):
      await receive(bytes, on: id)
    case .uploadEnd(let id, let fileName):
      await completeUpload(id, named: fileName)
    case .unpaired:
      await unpaired(peer)
    case .reply, .failure, .feed, .delta:
      return
    }
  }

  private func finish(_ id: UInt32, with answer: Frame) async {
    guard calls.removeValue(forKey: id) != nil else { return }
    await send(answer)
  }

  private func deliver(_ json: JSONValue, on id: UInt32) async {
    guard subscriptions[id] != nil else { return }
    let frame: Frame?
    if let last = lastSent[id] {
      frame = JSONDelta.from(last, to: json).flatMap { try? JSONEncoder().encode($0) }.map { .delta(id: id, body: $0) }
    } else {
      frame = (try? json.data()).map { .feed(id: id, body: $0) }
    }
    lastSent[id] = json
    if let frame { await send(frame) }
  }

  private func receive(_ bytes: Data, on id: UInt32) async {
    do {
      if uploads[id] == nil { uploads[id] = try folder.receiveUpload(named: "upload", id: newID()) }
      try uploads[id]?.append(bytes)
    } catch {
      uploads.removeValue(forKey: id)?.abandon()
      await send(.failure(id: id, .storage(error.localizedDescription)))
    }
  }

  private func completeUpload(_ id: UInt32, named name: String) async {
    do throws(HostError) {
      let received: IncomingUpload
      if let pending = uploads.removeValue(forKey: id) {
        received = pending
      } else {
        let folder = folder
        let newID = newID
        received = try attempt { try folder.receiveUpload(named: name, id: newID()) }
      }
      let file = try attempt { try received.finish() }
      let named = try attempt { try folder.rename(file, to: name) }
      let upload = try await host.upload(LocalFile(named))
      await send(.reply(id: id, body: try WireCodec.encode(upload)))
    } catch {
      await send(.failure(id: id, error))
    }
  }

  private func send(_ frame: Frame) async {
    try? await channel.send(frame.encoded)
  }
}
