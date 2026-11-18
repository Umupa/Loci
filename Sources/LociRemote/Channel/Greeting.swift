import CryptoKit
import Foundation
import LociModel

/// Why one Mac dials another.
public enum Purpose: Hashable, Codable, Sendable {
  /// A paired Mac opens one of the two connections.
  case open(Lane)
  /// A nearby Mac asks to pair; both show the code derived from the handshake.
  case pair
  /// A Mac pastes an invite link; the link's secret is the handshake's pre-shared key.
  case invite(EntityID)
}

/// The first message, inside the handshake: who is calling, how to reach it back, and why.
public struct Hello: Hashable, Codable, Sendable {
  public let from: Machine
  public let address: PeerAddress
  public let purpose: Purpose

  public init(from: Machine, address: PeerAddress, purpose: Purpose) {
    self.from = from
    self.address = address
    self.purpose = purpose
  }
}

public enum Refusal: String, Error, Hashable, Codable, Sendable {
  /// The calling key is not in the roster: it was removed, or never paired.
  case unknown
  case inviteExpired
  case inviteUsed
}

/// The responder's answer in the second message.
enum Answer: Hashable, Codable, Sendable {
  case welcome(Machine)
  case refused(Refusal)
}

/// What the responder does with a `Hello`. A refusal to a known key is sent inside the handshake, so the
/// caller can trust it; an invite that cannot be checked is refused in the clear.
public enum Decision: Sendable {
  case welcome(Machine, preSharedKey: Data?)
  case refuse(Refusal)
  /// Hang up without answering, for a caller not worth an answer right now.
  case drop
}

public enum GreetingError: Error, Hashable, Sendable {
  case refused(Refusal)
  case channel(ChannelError)
  /// The key that answered is not the key of the Mac that was dialed, or the hello's key and Mac disagree.
  case impostor
}

/// A finished handshake, on either side.
public struct Greeted: Sendable {
  public let channel: SecureChannel
  /// The Mac on the other end, as it named itself.
  public let peer: Machine
  public let peerAddress: PeerAddress
  public let purpose: Purpose
  /// The same on both Macs only if nobody sits in between.
  public let code: PairingCode
}

/// The Noise handshake between two Macs, with the hello and answer as its payloads. The first byte of the
/// first message names the pattern, which the responder must know before it can read anything.
public enum Greeting {
  public static func dial(
    _ socket: any MessageSocket, as key: DeviceKey, me: Machine, to remote: PeerAddress, purpose: Purpose,
    preSharedKey: Data? = nil
  ) async throws(GreetingError) -> Greeted {
    let pattern: HandshakePattern = preSharedKey == nil ? .ik : .ikpsk2
    guard let remoteKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: remote.publicKey) else {
      throw .impostor
    }
    var handshake = Handshake(
      pattern, role: .initiator, prologue: prologue, localStatic: key.privateKey, remoteStatic: remoteKey,
      preSharedKey: preSharedKey)
    do {
      let hello = try JSONEncoder().encode(Hello(from: me, address: key.address, purpose: purpose))
      try await socket.send(.binary(Data([pattern.marker]) + handshake.write(payload: hello)))
      let reply = try await socket.receive()
      guard case .binary(let message) = reply else {
        if case .text(let text) = reply, let refusal = Refusal(rawValue: text) { throw GreetingError.refused(refusal) }
        throw GreetingError.channel(.malformed)
      }
      switch try JSONDecoder().decode(Answer.self, from: handshake.read(message)) {
      case .refused(let refusal):
        await socket.close(code: 1000)
        throw GreetingError.refused(refusal)
      case .welcome(let peer):
        guard peer.id == MachineID(publicKey: remote.publicKey) else { throw GreetingError.impostor }
        let channel = SecureChannel(socket: socket, keys: try handshake.transport())
        return Greeted(
          channel: channel, peer: peer, peerAddress: remote, purpose: purpose,
          code: PairingCode(handshakeHash: handshake.hash))
      }
    } catch {
      await socket.close(code: 1002)
      throw GreetingError(error)
    }
  }

  /// `nil` when the caller was refused; the socket is closed then.
  public static func answer(
    _ socket: any MessageSocket, as key: DeviceKey, decide: @Sendable (Hello) async -> Decision
  ) async throws(GreetingError) -> Greeted? {
    do {
      guard case .binary(let first) = try await socket.receive(), let marker = first.first,
        let pattern = HandshakePattern(marker: marker)
      else { throw GreetingError.channel(.malformed) }
      var handshake = Handshake(pattern, role: .responder, prologue: prologue, localStatic: key.privateKey)
      let hello = try JSONDecoder().decode(Hello.self, from: handshake.read(first.dropFirst()))
      guard let caller = handshake.remoteStatic?.rawRepresentation, hello.address.publicKey == caller,
        hello.from.id == MachineID(publicKey: caller)
      else { throw GreetingError.impostor }
      switch await decide(hello) {
      case .drop:
        await socket.close(code: 1000)
        return nil
      case .refuse(let refusal) where pattern == .ikpsk2:
        try await socket.send(.text(refusal.rawValue))
        await socket.close(code: 1000)
        return nil
      case .refuse(let refusal):
        try await socket.send(.binary(handshake.write(payload: JSONEncoder().encode(Answer.refused(refusal)))))
        await socket.close(code: 1000)
        return nil
      case .welcome(let me, let preSharedKey):
        if let preSharedKey { handshake.providePreSharedKey(preSharedKey) }
        try await socket.send(.binary(handshake.write(payload: JSONEncoder().encode(Answer.welcome(me)))))
        let channel = SecureChannel(socket: socket, keys: try handshake.transport())
        return Greeted(
          channel: channel, peer: hello.from, peerAddress: hello.address, purpose: hello.purpose,
          code: PairingCode(handshakeHash: handshake.hash))
      }
    } catch {
      await socket.close(code: 1002)
      throw GreetingError(error)
    }
  }

  static let prologue = Data("loci/1".utf8)
}

extension GreetingError {
  init(_ error: any Error) {
    switch error {
    case let error as GreetingError: self = error
    case let error as SocketError: self = .channel(.socket(error))
    case let error as NoiseError: self = .channel(.noise(error))
    case let error as ChannelError: self = .channel(error)
    default: self = .channel(.malformed)
    }
  }
}

extension HandshakePattern {
  var marker: UInt8 { self == .ik ? 1 : 2 }

  init?(marker: UInt8) {
    switch marker {
    case 1: self = .ik
    case 2: self = .ikpsk2
    default: return nil
    }
  }
}

extension PairingCode {
  /// Two bytes of a hash of the handshake, as four digits.
  init(handshakeHash: Data) {
    let digest = SHA256.hash(data: Data("loci pairing code".utf8) + handshakeHash)
    let bytes = Array(digest.prefix(2))
    self.init(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
  }
}
