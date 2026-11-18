import Foundation
import Security

/// Where this Mac's device key is kept.
public protocol KeyVault: Sendable {
  func load() throws(KeyVaultError) -> Data?
  func save(_ key: Data) throws(KeyVaultError)
}

public struct KeyVaultError: Error, Hashable, Sendable {
  public let status: Int32
}

/// The login keychain, as a generic password that stays on this Mac.
public struct DeviceKeychain: KeyVault {
  private let service: String

  public init(service: String) {
    self.service = service
  }

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "device",
    ]
  }

  public func load() throws(KeyVaultError) -> Data? {
    var found: CFTypeRef?
    var request = query
    request[kSecReturnData as String] = true
    let status = SecItemCopyMatching(request as CFDictionary, &found)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeyVaultError(status: status) }
    return found as? Data
  }

  public func save(_ key: Data) throws(KeyVaultError) {
    var item = query
    item[kSecValueData as String] = key
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    item[kSecAttrLabel as String] = "Loci device key"
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeyVaultError(status: status) }
  }
}
