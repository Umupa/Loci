import Foundation
import LociModel
import Security

/// Where a connector's credentials are kept: never in a file the companion can read.
public protocol ConnectorVault: Sendable {
  func secret(for connector: ConnectorID) throws(KeyVaultError) -> Data?
  /// `nil` deletes it.
  func setSecret(_ secret: Data?, for connector: ConnectorID) throws(KeyVaultError)
}

/// The login keychain, one item per connector, readable only on this Mac once it is unlocked.
public struct ConnectorKeychain: ConnectorVault {
  private let serviceName: String

  public init(serviceName: String) {
    self.serviceName = serviceName
  }

  public func secret(for connector: ConnectorID) throws(KeyVaultError) -> Data? {
    var found: CFTypeRef?
    var request = query(for: connector)
    request[kSecReturnData as String] = true
    let status = SecItemCopyMatching(request as CFDictionary, &found)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = found as? Data else {
      throw KeyVaultError(status: status == errSecSuccess ? errSecDecode : status)
    }
    return data
  }

  public func setSecret(_ secret: Data?, for connector: ConnectorID) throws(KeyVaultError) {
    let query = query(for: connector)
    guard let secret else {
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyVaultError(status: status) }
      return
    }
    let value = [kSecValueData as String: secret]
    let updated = SecItemUpdate(query as CFDictionary, value as CFDictionary)
    if updated == errSecSuccess { return }
    guard updated == errSecItemNotFound else { throw KeyVaultError(status: updated) }
    var item = query.merging(value) { _, new in new }
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    item[kSecAttrLabel as String] = "Loci connector " + connector.rawValue
    let added = SecItemAdd(item as CFDictionary, nil)
    guard added == errSecSuccess else { throw KeyVaultError(status: added) }
  }

  private func query(for connector: ConnectorID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: connector.rawValue,
    ]
  }
}
