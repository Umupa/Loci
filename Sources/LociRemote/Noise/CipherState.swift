import CryptoKit
import Foundation

/// Why a Noise message could not be written or read. Any of these ends the session: Noise has no recovery.
public enum NoiseError: Error, Hashable, Sendable {
  /// The message was changed on the way, or was meant for another session.
  case decryptFailed
  /// Noise messages are at most 65 535 bytes.
  case messageTooLong
  /// The session sent or received 2^64 - 1 messages.
  case nonceExhausted
  /// The handshake was asked for something out of turn, such as reading when it is its turn to write.
  case outOfTurn
  /// A message shorter than its handshake tokens need, or a key that is not a Curve25519 key.
  case malformed
  /// The pattern mixes in a pre-shared key and none was given before its turn came.
  case missingPreSharedKey
}

/// ChaCha20-Poly1305 with Noise's counter nonce: 32 zero bits, then the counter as 64 bits little-endian.
public struct CipherState: Sendable {
  public static let maximumMessage = 65_535
  static let tagLength = 16

  private var key: SymmetricKey?
  private var nonce: UInt64 = 0

  init(key: SymmetricKey? = nil) {
    self.key = key
  }

  var hasKey: Bool { key != nil }

  mutating func encrypt(_ plaintext: Data, associatedData: Data = Data()) throws(NoiseError) -> Data {
    guard let key else { return plaintext }
    guard nonce < .max else { throw .nonceExhausted }
    do {
      let sealed = try ChaChaPoly.seal(
        plaintext, using: key, nonce: try Self.nonce(nonce), authenticating: associatedData)
      nonce += 1
      return sealed.ciphertext + sealed.tag
    } catch {
      throw .decryptFailed
    }
  }

  mutating func decrypt(_ ciphertext: Data, associatedData: Data = Data()) throws(NoiseError) -> Data {
    guard let key else { return ciphertext }
    guard nonce < .max else { throw .nonceExhausted }
    guard ciphertext.count >= Self.tagLength else { throw .decryptFailed }
    do {
      let box = try ChaChaPoly.SealedBox(
        nonce: try Self.nonce(nonce), ciphertext: ciphertext.dropLast(Self.tagLength),
        tag: ciphertext.suffix(Self.tagLength))
      let plaintext = try ChaChaPoly.open(box, using: key, authenticating: associatedData)
      nonce += 1
      return plaintext
    } catch {
      throw .decryptFailed
    }
  }

  private static func nonce(_ counter: UInt64) throws -> ChaChaPoly.Nonce {
    try ChaChaPoly.Nonce(data: Data(count: 4) + withUnsafeBytes(of: counter.littleEndian) { Data($0) })
  }
}

/// The two directions of a finished handshake.
public struct TransportKeys: Sendable {
  public var send: CipherState
  public var receive: CipherState
}
