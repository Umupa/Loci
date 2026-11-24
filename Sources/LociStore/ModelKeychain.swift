import Foundation
import LociModel
import Security

/// Where providers' keys are kept, each under its provider's account.
public protocol ModelKeyStore: Sendable {
  /// Whether a key is saved, told without reading it: reading it may ask the person to allow Loci in.
  func hasKey(account: String) throws(KeyVaultError) -> Bool
  func key(account: String) throws(KeyVaultError) -> String?
  /// Saves `key`, or removes it when `nil`.
  func setKey(_ key: String?, account: String) throws(KeyVaultError)
}

public struct ModelKeychain: ModelKeyStore {
  private let serviceName: String

  public init(serviceName: String) {
    self.serviceName = serviceName
  }

  public func hasKey(account: String) throws(KeyVaultError) -> Bool {
    var request = query(account)
    request[kSecReturnAttributes as String] = true
    var found: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &found)
    if status == errSecItemNotFound { return false }
    guard status == errSecSuccess else { throw KeyVaultError(status: status) }
    return true
  }

  public func key(account: String) throws(KeyVaultError) -> String? {
    var found: CFTypeRef?
    var request = query(account)
    request[kSecReturnData as String] = true
    let status = SecItemCopyMatching(request as CFDictionary, &found)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = found as? Data, let key = String(data: data, encoding: .utf8) else {
      throw KeyVaultError(status: status == errSecSuccess ? errSecDecode : status)
    }
    return key
  }

  public func setKey(_ key: String?, account: String) throws(KeyVaultError) {
    let query = query(account)
    guard let key else {
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyVaultError(status: status) }
      return
    }
    let value = [kSecValueData as String: Data(key.utf8)]
    let updated = SecItemUpdate(query as CFDictionary, value as CFDictionary)
    if updated == errSecSuccess { return }
    guard updated == errSecItemNotFound else { throw KeyVaultError(status: updated) }
    var item = query.merging(value) { _, new in new }
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    item[kSecAttrLabel as String] = "Loci model service API key"
    let added = SecItemAdd(item as CFDictionary, nil)
    guard added == errSecSuccess else { throw KeyVaultError(status: added) }
  }

  private func query(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: account,
    ]
  }
}
