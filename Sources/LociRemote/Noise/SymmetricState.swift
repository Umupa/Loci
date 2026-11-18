import CryptoKit
import Foundation

/// The chaining key and handshake hash of Noise section 5.2, with SHA-256.
struct SymmetricState: Sendable {
  private(set) var hash: Data
  private var chainingKey: Data
  private var cipher = CipherState()

  init(protocolName: String) {
    let name = Data(protocolName.utf8)
    hash = name.count <= 32 ? name + Data(count: 32 - name.count) : Data(SHA256.hash(data: name))
    chainingKey = hash
  }

  var hasKey: Bool { cipher.hasKey }

  mutating func mixKey(_ material: Data) {
    let (next, key) = Self.derive2(chainingKey, material)
    chainingKey = next
    cipher = CipherState(key: SymmetricKey(data: key))
  }

  mutating func mixHash(_ data: Data) {
    hash = Data(SHA256.hash(data: hash + data))
  }

  mutating func mixKeyAndHash(_ material: Data) {
    let outputs = Self.hkdf(chainingKey, material, count: 3)
    chainingKey = outputs[0]
    mixHash(outputs[1])
    cipher = CipherState(key: SymmetricKey(data: outputs[2]))
  }

  mutating func encryptAndHash(_ plaintext: Data) throws(NoiseError) -> Data {
    let ciphertext = try cipher.encrypt(plaintext, associatedData: hash)
    mixHash(ciphertext)
    return ciphertext
  }

  mutating func decryptAndHash(_ ciphertext: Data) throws(NoiseError) -> Data {
    let plaintext = try cipher.decrypt(ciphertext, associatedData: hash)
    mixHash(ciphertext)
    return plaintext
  }

  func split() -> (CipherState, CipherState) {
    let (first, second) = Self.derive2(chainingKey, Data())
    return (CipherState(key: SymmetricKey(data: first)), CipherState(key: SymmetricKey(data: second)))
  }

  private static func derive2(_ chainingKey: Data, _ material: Data) -> (Data, Data) {
    let outputs = hkdf(chainingKey, material, count: 2)
    return (outputs[0], outputs[1])
  }

  /// Noise's HKDF: HMAC-SHA256 extract, then each output is HMAC(temp, previous ‖ index).
  static func hkdf(_ chainingKey: Data, _ material: Data, count: Int) -> [Data] {
    let temp = SymmetricKey(data: hmac(SymmetricKey(data: chainingKey), material))
    var outputs: [Data] = []
    var previous = Data()
    for index in 1...count {
      previous = hmac(temp, previous + Data([UInt8(index)]))
      outputs.append(previous)
    }
    return outputs
  }

  private static func hmac(_ key: SymmetricKey, _ data: Data) -> Data {
    Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
  }
}
