import Foundation
import LociModel
import Security

public protocol ModelKeyStore: Sendable {
  func key(for service: ModelService) throws(KeyVaultError) -> String?
  func setKey(_ key: String?, for service: ModelService) throws(KeyVaultError)
}

public struct ModelKeychain: ModelKeyStore {
  private let serviceName: String

  public init(serviceName: String) {
    self.serviceName = serviceName
  }

  public func key(for service: ModelService) throws(KeyVaultError) -> String? {
    var found: CFTypeRef?
    var request = query(for: service)
    request[kSecReturnData as String] = true
    let status = SecItemCopyMatching(request as CFDictionary, &found)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = found as? Data, let key = String(data: data, encoding: .utf8) else {
      throw KeyVaultError(status: status == errSecSuccess ? errSecDecode : status)
    }
    return key
  }

  public func setKey(_ key: String?, for service: ModelService) throws(KeyVaultError) {
    let query = query(for: service)
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
    item[kSecAttrLabel as String] = "Loci " + service.provider.rawValue + " API key"
    let added = SecItemAdd(item as CFDictionary, nil)
    guard added == errSecSuccess else { throw KeyVaultError(status: added) }
  }

  private func query(for service: ModelService) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: service.provider.rawValue + ":" + service.endpoint.absoluteString,
    ]
  }
}
