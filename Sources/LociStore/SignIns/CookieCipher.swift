import CommonCrypto
import Foundation

/// How Chromium browsers on macOS encrypt a cookie's value: AES-128-CBC with a key stretched from the password
/// the browser keeps in the login keychain. A value starts with `v10`; since database version 24 the plain
/// text starts with the SHA-256 of the cookie's domain, which is not part of the value.
struct CookieCipher: Sendable {
  private let key: Data

  init(password: Data) {
    key = Self.stretch(password)
  }

  /// The value, or `nil` for one that is not in this format or does not decrypt with this key.
  func decrypt(_ sealed: Data, databaseVersion: Int) -> String? {
    guard sealed.starts(with: Self.prefix) else { return nil }
    guard var plain = crypt(sealed.dropFirst(Self.prefix.count), operation: CCOperation(kCCDecrypt)) else {
      return nil
    }
    if databaseVersion >= 24 {
      guard plain.count >= 32 else { return nil }
      plain = plain.dropFirst(32)
    }
    return String(data: plain, encoding: .utf8)
  }

  /// The opposite of `decrypt`, for making a browser's cookies in tests.
  func seal(_ value: String, domainHash: Data = Data()) -> Data? {
    crypt(domainHash + Data(value.utf8), operation: CCOperation(kCCEncrypt)).map { Self.prefix + $0 }
  }

  private static let prefix = Data("v10".utf8)
  private static let salt = Data("saltysalt".utf8)
  private static let rounds: UInt32 = 1003
  private static let initialVector = Data(repeating: 0x20, count: kCCBlockSizeAES128)

  private static func stretch(_ password: Data) -> Data {
    var key = Data(count: kCCKeySizeAES128)
    let count = key.count
    let status = key.withUnsafeMutableBytes { keyBytes in
      password.withUnsafeBytes { passwordBytes in
        salt.withUnsafeBytes { saltBytes in
          CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
            password.count, saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), rounds,
            keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), count)
        }
      }
    }
    return status == kCCSuccess ? key : Data()
  }

  private func crypt(_ input: Data, operation: CCOperation) -> Data? {
    guard key.count == kCCKeySizeAES128 else { return nil }
    var output = Data(count: input.count + kCCBlockSizeAES128)
    let capacity = output.count
    var written = 0
    let status = output.withUnsafeMutableBytes { outputBytes in
      input.withUnsafeBytes { inputBytes in
        key.withUnsafeBytes { keyBytes in
          Self.initialVector.withUnsafeBytes { vectorBytes in
            CCCrypt(
              operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), keyBytes.baseAddress,
              key.count, vectorBytes.baseAddress, inputBytes.baseAddress, input.count, outputBytes.baseAddress,
              capacity, &written)
          }
        }
      }
    }
    guard status == kCCSuccess else { return nil }
    return output.prefix(written)
  }
}
