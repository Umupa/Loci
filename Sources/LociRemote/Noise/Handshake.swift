import CryptoKit
import Foundation

/// The two handshakes Loci speaks. Both start from the responder's static key, known in advance.
public enum HandshakePattern: Sendable {
  /// `Noise_IK_25519_ChaChaPoly_SHA256`: opening a paired Mac, or pairing with a nearby one.
  case ik
  /// `Noise_IKpsk2_25519_ChaChaPoly_SHA256`: pairing through an invite link, whose secret is the PSK.
  case ikpsk2

  var name: String {
    switch self {
    case .ik: "Noise_IK_25519_ChaChaPoly_SHA256"
    case .ikpsk2: "Noise_IKpsk2_25519_ChaChaPoly_SHA256"
    }
  }

  fileprivate var messages: [[Token]] {
    switch self {
    case .ik: [[.e, .es, .s, .ss], [.e, .ee, .se]]
    case .ikpsk2: [[.e, .es, .s, .ss], [.e, .ee, .se, .psk]]
    }
  }

  fileprivate var usesPreSharedKey: Bool { self == .ikpsk2 }
}

private enum Token { case e, s, ee, es, se, ss, psk }

public enum HandshakeRole: Sendable { case initiator, responder }

/// One side of a Noise handshake (section 5.3), as a value that is advanced message by message.
public struct Handshake: Sendable {
  public typealias PrivateKey = Curve25519.KeyAgreement.PrivateKey
  public typealias PublicKey = Curve25519.KeyAgreement.PublicKey

  private let pattern: HandshakePattern
  private let role: HandshakeRole
  private var symmetric: SymmetricState
  private let localStatic: PrivateKey
  private var localEphemeral: PrivateKey?
  private let makeEphemeral: @Sendable () -> PrivateKey
  private var preSharedKey: Data?
  private var messageIndex = 0
  public private(set) var remoteStatic: PublicKey?
  private var remoteEphemeral: PublicKey?

  /// `remoteStatic` is required of the initiator, which must know whom it dials. The ephemeral key comes
  /// from `makeEphemeral`, so tests can fix it.
  public init(
    _ pattern: HandshakePattern, role: HandshakeRole, prologue: Data, localStatic: PrivateKey,
    remoteStatic: PublicKey? = nil, preSharedKey: Data? = nil,
    makeEphemeral: @escaping @Sendable () -> PrivateKey = { PrivateKey() }
  ) {
    self.pattern = pattern
    self.role = role
    self.localStatic = localStatic
    self.remoteStatic = remoteStatic
    self.preSharedKey = preSharedKey
    self.makeEphemeral = makeEphemeral
    symmetric = SymmetricState(protocolName: pattern.name)
    symmetric.mixHash(prologue)
    let responderKey = role == .responder ? localStatic.publicKey : remoteStatic
    symmetric.mixHash(responderKey?.rawRepresentation ?? Data())
  }

  /// Sets the pre-shared key once the responder knows which one the initiator means, after the first message.
  public mutating func providePreSharedKey(_ key: Data) {
    preSharedKey = key
  }

  public var isComplete: Bool { messageIndex == pattern.messages.count }
  /// Identical on both sides once the handshake is complete; anything derived from it is shared.
  public var hash: Data { symmetric.hash }

  private var isMyTurn: Bool { (messageIndex % 2 == 0) == (role == .initiator) }

  public mutating func write(payload: Data = Data()) throws(NoiseError) -> Data {
    guard !isComplete, isMyTurn else { throw .outOfTurn }
    var message = Data()
    for token in pattern.messages[messageIndex] {
      switch token {
      case .e:
        let ephemeral = makeEphemeral()
        localEphemeral = ephemeral
        message += ephemeral.publicKey.rawRepresentation
        symmetric.mixHash(ephemeral.publicKey.rawRepresentation)
        if pattern.usesPreSharedKey { symmetric.mixKey(ephemeral.publicKey.rawRepresentation) }
      case .s:
        message += try symmetric.encryptAndHash(localStatic.publicKey.rawRepresentation)
      case .psk:
        guard let preSharedKey else { throw .missingPreSharedKey }
        symmetric.mixKeyAndHash(preSharedKey)
      case .ee, .es, .se, .ss:
        symmetric.mixKey(try agreement(token))
      }
    }
    message += try symmetric.encryptAndHash(payload)
    guard message.count <= CipherState.maximumMessage else { throw .messageTooLong }
    messageIndex += 1
    return message
  }

  public mutating func read(_ message: Data) throws(NoiseError) -> Data {
    guard !isComplete, !isMyTurn else { throw .outOfTurn }
    guard message.count <= CipherState.maximumMessage else { throw .messageTooLong }
    var rest = message
    for token in pattern.messages[messageIndex] {
      switch token {
      case .e:
        let key = try Self.take(32, from: &rest)
        remoteEphemeral = try Self.publicKey(key)
        symmetric.mixHash(key)
        if pattern.usesPreSharedKey { symmetric.mixKey(key) }
      case .s:
        let sealed = try Self.take(symmetric.hasKey ? 32 + CipherState.tagLength : 32, from: &rest)
        remoteStatic = try Self.publicKey(try symmetric.decryptAndHash(sealed))
      case .psk:
        guard let preSharedKey else { throw .missingPreSharedKey }
        symmetric.mixKeyAndHash(preSharedKey)
      case .ee, .es, .se, .ss:
        symmetric.mixKey(try agreement(token))
      }
    }
    let payload = try symmetric.decryptAndHash(rest)
    messageIndex += 1
    return payload
  }

  /// The transport keys, oriented for this side. Only once the handshake is complete.
  public func transport() throws(NoiseError) -> TransportKeys {
    guard isComplete else { throw .outOfTurn }
    let (first, second) = symmetric.split()
    return role == .initiator
      ? TransportKeys(send: first, receive: second) : TransportKeys(send: second, receive: first)
  }

  /// `es` is the initiator's ephemeral with the responder's static, whichever side computes it; likewise `se`.
  private func agreement(_ token: Token) throws(NoiseError) -> Data {
    let initiator = role == .initiator
    let pair: (PrivateKey?, PublicKey?)
    switch token {
    case .ee: pair = (localEphemeral, remoteEphemeral)
    case .ss: pair = (localStatic, remoteStatic)
    case .es: pair = initiator ? (localEphemeral, remoteStatic) : (localStatic, remoteEphemeral)
    case .se: pair = initiator ? (localStatic, remoteEphemeral) : (localEphemeral, remoteStatic)
    case .e, .s, .psk: pair = (nil, nil)
    }
    guard let local = pair.0, let remote = pair.1,
      let shared = try? local.sharedSecretFromKeyAgreement(with: remote)
    else { throw .malformed }
    return shared.withUnsafeBytes { Data($0) }
  }

  private static func take(_ count: Int, from data: inout Data) throws(NoiseError) -> Data {
    guard data.count >= count else { throw .malformed }
    let taken = Data(data.prefix(count))
    data = Data(data.dropFirst(count))
    return taken
  }

  private static func publicKey(_ raw: Data) throws(NoiseError) -> PublicKey {
    guard let key = try? PublicKey(rawRepresentation: raw) else { throw .malformed }
    return key
  }
}
