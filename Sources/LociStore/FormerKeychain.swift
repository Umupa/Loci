import Foundation
import LociModel
import Security

/// What an earlier Loci kept in the login keychain.
public protocol FormerSecrets: Sendable {
  /// Everything it can still read; what macOS does not let it read is left out.
  func all() -> FoundSecrets
}

public struct FoundSecrets: Hashable, Sendable {
  public var device: Data?
  public var models: [String: Data]
  public var connectors: [ConnectorID: Data]

  public init(device: Data? = nil, models: [String: Data] = [:], connectors: [ConnectorID: Data] = [:]) {
    self.device = device
    self.models = models
    self.connectors = connectors
  }
}

/// The login keychain items Loci used before its secrets moved into files. macOS may ask once for each.
public struct FormerKeychain: FormerSecrets {
  public init() {}

  public func all() -> FoundSecrets {
    FoundSecrets(
      device: items(of: "com.loci.native.dev.device-key")["device"],
      models: items(of: "com.loci.native.dev.model-service"),
      connectors: Dictionary(
        uniqueKeysWithValues: items(of: "com.loci.native.dev.connector").map { (ConnectorID($0.key), $0.value) }))
  }

  private func items(of service: String) -> [String: Data] {
    let list: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true,
    ]
    var found: CFTypeRef?
    guard SecItemCopyMatching(list as CFDictionary, &found) == errSecSuccess,
      let attributes = found as? [[String: Any]]
    else { return [:] }
    var items: [String: Data] = [:]
    for account in attributes.compactMap({ $0[kSecAttrAccount as String] as? String }) {
      let one: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
        kSecAttrAccount as String: account, kSecReturnData as String: true,
      ]
      var data: CFTypeRef?
      if SecItemCopyMatching(one as CFDictionary, &data) == errSecSuccess, let data = data as? Data {
        items[account] = data
      }
    }
    return items
  }
}
