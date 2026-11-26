import Foundation
import LociModel
import LociRemote
import LociStore

/// A pairing request waiting for the person to answer.
struct PendingRequest {
  let request: PairingRequest
  let verdict: CheckedContinuation<PairingVerdict?, Never>
}

extension MachinesService {
  /// How long a pairing request waits for an answer before it counts as declined.
  static let patience = Duration.seconds(120)
  /// Pairing requests shown at once, from different Macs.
  static let mostRequests = 3
  /// How long a Mac whose request was declined is not heard again.
  static let declinedQuiet: Int64 = 30 * 1000
  /// How long an invite link works.
  static let inviteLife: Int64 = 10 * 60 * 1000

  public nonisolated func nearby() -> AsyncStream<[NearbyMac]> {
    let (macs, continuation) = AsyncStream.makeStream(of: [NearbyMac].self, bufferingPolicy: .bufferingNewest(1))
    let browsing = Task {
      for await found in self.discovery.browse() {
        let known = await self.knownIDs
        continuation.yield(found.filter { !known.contains($0.id) })
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in browsing.cancel() }
    return macs
  }

  private var knownIDs: Set<MachineID> {
    Set(peers.map(\.machine.id) + [this.id])
  }

  public nonisolated func pair(with mac: NearbyMac) -> AsyncStream<PairingStep> {
    let (steps, continuation) = AsyncStream.makeStream(of: PairingStep.self)
    let pairing = Task {
      await self.pairing(with: mac) { continuation.yield($0) }
      continuation.finish()
    }
    continuation.onTermination = { _ in pairing.cancel() }
    return steps
  }

  private func pairing(with mac: NearbyMac, show: @Sendable (PairingStep) -> Void) async {
    let greeted: Greeted
    do {
      greeted = try await Greeting.dial(
        try await access.open(mac.address), as: key, me: this, to: mac.address, purpose: .pair)
    } catch {
      return show(.failed(.unreachable))
    }
    show(.code(greeted.code))
    let verdict = await Self.verdict(on: greeted.channel, within: Self.patience, clock: access.clock)
    await greeted.channel.close()
    guard verdict == .allowed else { return show(.failed(.declined)) }
    await add(greeted.peer, at: mac.address)
    show(.paired(greeted.peer))
  }

  /// The other Mac's answer, or `nil` when it hung up, the wait ran out, or the task was cancelled.
  private static func verdict(on channel: SecureChannel, within limit: Duration, clock: any Clock<Duration>) async
    -> PairingVerdict?
  {
    await withTaskGroup(of: PairingVerdict?.self) { group in
      group.addTask {
        await withTaskCancellationHandler {
          (try? await channel.receive()).flatMap(PairingVerdict.init)
        } onCancel: {
          Task { await channel.close() }
        }
      }
      group.addTask {
        try? await clock.sleep(for: limit)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }

  public nonisolated func requests() -> AsyncStream<[PairingRequest]> {
    let (requests, continuation) = AsyncStream.makeStream(
      of: [PairingRequest].self, bufferingPolicy: .bufferingNewest(1))
    Task { await self.watchRequests(continuation) }
    return requests
  }

  private func watchRequests(_ continuation: AsyncStream<[PairingRequest]>.Continuation) {
    let id = allocateWatcher()
    requestWatchers[id] = continuation
    continuation.yield(currentRequests)
    continuation.onTermination = { _ in Task { await self.dropRequestWatcher(id) } }
  }

  private func dropRequestWatcher(_ id: Int) {
    requestWatchers[id] = nil
  }

  private var currentRequests: [PairingRequest] {
    pending.values.map(\.request).sorted { $0.id < $1.id }
  }

  private func publishRequests() {
    let requests = currentRequests
    for watcher in requestWatchers.values { watcher.yield(requests) }
  }

  public func answer(_ request: PairingRequest.ID, allow: Bool) async {
    guard let waiting = pending.removeValue(forKey: request) else { return }
    waiting.verdict.resume(returning: allow ? .allowed : .declined)
    publishRequests()
  }

  public func invite() async throws(PairingFailure) -> Invite {
    let expires = Timestamp(millisecondsSince1970: now().millisecondsSince1970 + Self.inviteLife)
    guard
      let invite = Invite(
        id: newID(), name: String(this.name.prefix(60)), model: this.model, address: key.address,
        secret: makeSecret(), expires: expires)
    else { throw .unreachable }
    invites.issue(invite)
    return invite
  }

  /// Pairs with the Mac that made the invite. The other Mac adds this one only when it confirms, after the
  /// handshake; a cancelled accept never confirms, so neither Mac is left half paired, and the other Mac
  /// opens the invite again.
  public func accept(_ invite: Invite) async throws(PairingFailure) -> Machine {
    guard !Task.isCancelled else { throw .cancelled }
    guard !invite.hasExpired(at: now()) else { throw .expired }
    guard invite.from.id != this.id else { throw .selfInvite }
    let greeted: Greeted
    switch await dialInvite(invite) {
    case .success(let done): greeted = done
    case .failure(let error): throw Task.isCancelled ? .cancelled : Self.failure(error)
    }
    guard !Task.isCancelled else {
      await greeted.channel.close()
      throw .cancelled
    }
    do {
      try await greeted.channel.send(PairingVerdict.allowed.encoded)
    } catch {
      await greeted.channel.close()
      throw .unreachable
    }
    await add(greeted.peer, at: invite.address)
    await greeted.channel.close()
    return greeted.peer
  }

  private func dialInvite(_ invite: Invite) async -> Result<Greeted, GreetingError> {
    let socket: any MessageSocket
    do {
      socket = try await access.open(invite.address)
    } catch {
      return .failure(.channel(.socket(error)))
    }
    return await withTaskCancellationHandler {
      do throws(GreetingError) {
        return .success(
          try await Greeting.dial(
            socket, as: key, me: this, to: invite.address, purpose: .invite(invite.id),
            preSharedKey: invite.secret))
      } catch {
        return .failure(error)
      }
    } onCancel: {
      Task { await socket.close(code: 1000) }
    }
  }

  private static func failure(_ error: GreetingError) -> PairingFailure {
    switch error {
    case .refused(.inviteExpired): .expired
    case .refused(.inviteUsed): .used
    default: .unreachable
    }
  }

  /// Answers a Mac that opened this one through the relay.
  func answer(_ socket: any MessageSocket) async {
    let greeted: Greeted?
    do {
      greeted = try await Greeting.answer(socket, as: key) { hello in await self.decide(hello) }
    } catch {
      Self.log.notice("a handshake failed: \(String(describing: error), privacy: .public)")
      return
    }
    guard let greeted else { return }
    switch greeted.purpose {
    case .open:
      await gateway?.serve(greeted)
    case .pair:
      await hold(greeted)
    case .invite(let id):
      let confirmed = await Self.verdict(on: greeted.channel, within: Self.patience, clock: access.clock) == .allowed
      await greeted.channel.close()
      guard let issued = redeemed.removeValue(forKey: id) else { return }
      if confirmed {
        await add(greeted.peer, at: greeted.peerAddress)
      } else if issued.expires > now() {
        invites.reopen(issued)
      }
    }
  }

  private func decide(_ hello: Hello) -> Decision {
    switch hello.purpose {
    case .open:
      return isPaired(hello) ? .welcome(this, preSharedKey: nil) : .refuse(.unknown)
    case .pair:
      return mayAsk(hello.address.publicKey) ? .welcome(this, preSharedKey: nil) : .drop
    case .invite(let id):
      switch invites.redeem(id, at: now()) {
      case .success(let issued):
        redeemed[id] = issued
        return .welcome(this, preSharedKey: issued.secret)
      case .failure(let refusal): return .refuse(refusal)
      }
    }
  }

  /// One request per Mac, a few at a time, and none for a while from a Mac that was just declined.
  private func mayAsk(_ key: Data) -> Bool {
    let quietUntil = (declined[key]?.millisecondsSince1970 ?? .min) + Self.declinedQuiet
    return !asking.contains(key) && asking.count < Self.mostRequests && now().millisecondsSince1970 >= quietUntil
  }

  /// Shows the request until the person answers, the asking Mac hangs up, or the wait runs out. Checked
  /// again here, after the handshake, because two handshakes may have passed `decide` together.
  private func hold(_ greeted: Greeted) async {
    let key = greeted.peerAddress.publicKey
    guard mayAsk(key) else { return await greeted.channel.close() }
    asking.insert(key)
    let request = PairingRequest(id: newID(), from: greeted.peer, code: greeted.code)
    let clock = access.clock
    let verdict: PairingVerdict? = await withTaskGroup(of: PairingVerdict?.self) { group in
      group.addTask { await self.awaitAnswer(to: request) }
      group.addTask {
        _ = try? await greeted.channel.receive()
        return nil
      }
      group.addTask {
        guard (try? await clock.sleep(for: Self.patience)) != nil else { return nil }
        return .declined
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
    withdraw(request.id)
    asking.remove(key)
    if verdict == .declined {
      let time = now()
      declined = declined.filter { time.millisecondsSince1970 - $0.value.millisecondsSince1970 < Self.declinedQuiet }
      declined[key] = time
    }
    if let verdict { try? await greeted.channel.send(verdict.encoded) }
    if verdict == .allowed { await add(greeted.peer, at: greeted.peerAddress) }
    await greeted.channel.close()
  }

  private func awaitAnswer(to request: PairingRequest) async -> PairingVerdict? {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled else { return continuation.resume(returning: nil) }
        pending[request.id] = PendingRequest(request: request, verdict: continuation)
        publishRequests()
      }
    } onCancel: {
      Task { await self.withdraw(request.id) }
    }
  }

  private func withdraw(_ request: EntityID) {
    guard let waiting = pending.removeValue(forKey: request) else { return }
    waiting.verdict.resume(returning: nil)
    publishRequests()
  }
}
