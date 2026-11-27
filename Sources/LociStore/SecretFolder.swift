import Foundation
import LociModel

/// Where this Mac's device key is kept.
public protocol KeyVault: Sendable {
  func load() throws(KeyVaultError) -> Data?
  func save(_ key: Data) throws(KeyVaultError)
}

/// Where providers' keys are kept, each under its provider's account.
public protocol ModelKeyStore: Sendable {
  /// Whether a key is saved, told without reading it.
  func hasKey(account: String) throws(KeyVaultError) -> Bool
  func key(account: String) throws(KeyVaultError) -> String?
  /// Saves `key`, or removes it when `nil`.
  func setKey(_ key: String?, account: String) throws(KeyVaultError)
}

/// Where a connector's credentials are kept, out of the prompts and environment the companion is given.
public protocol ConnectorVault: Sendable {
  func secret(for connector: ConnectorID) throws(KeyVaultError) -> Data?
  /// `nil` deletes it.
  func setSecret(_ secret: Data?, for connector: ConnectorID) throws(KeyVaultError)
}

/// The device key, model services' keys and connectors' credentials, each a file only this user can read in a
/// folder only this user can open. Nothing asks for a password after an update, and any program running as
/// this user, the companion's included, can read them.
public struct SecretFolder: KeyVault, ModelKeyStore, ConnectorVault {
  private let root: URL

  public init(root: URL) {
    self.root = root
  }

  public func load() throws(KeyVaultError) -> Data? {
    try read(deviceKey)
  }

  public func save(_ key: Data) throws(KeyVaultError) {
    try write(key, to: deviceKey)
  }

  public func hasKey(account: String) throws(KeyVaultError) -> Bool {
    FileManager.default.fileExists(atPath: model(account).path(percentEncoded: false))
  }

  public func key(account: String) throws(KeyVaultError) -> String? {
    guard let data = try read(model(account)) else { return nil }
    guard let key = String(data: data, encoding: .utf8) else { throw KeyVaultError(reason: "the key is not text") }
    return key
  }

  public func setKey(_ key: String?, account: String) throws(KeyVaultError) {
    try write(key.map { Data($0.utf8) }, to: model(account))
  }

  public func secret(for connector: ConnectorID) throws(KeyVaultError) -> Data? {
    try read(self.connector(connector))
  }

  public func setSecret(_ secret: Data?, for connector: ConnectorID) throws(KeyVaultError) {
    try write(secret, to: self.connector(connector))
  }

  /// Brings over what an earlier Loci kept in the keychain, the first time the folder is used. Later a secret
  /// removed here stays removed, whatever the keychain still holds.
  public func carryOver(from former: any FormerSecrets) throws(KeyVaultError) {
    guard !FileManager.default.fileExists(atPath: carried.path(percentEncoded: false)) else { return }
    let found = former.all()
    if let device = found.device, try read(deviceKey) == nil { try save(device) }
    for (account, key) in found.models where try read(model(account)) == nil {
      try write(key, to: model(account))
    }
    for (id, secret) in found.connectors where try read(connector(id)) == nil {
      try write(secret, to: connector(id))
    }
    try write(Data(), to: carried)
  }

  private var deviceKey: URL { root.appending(path: "device") }
  private var carried: URL { root.appending(path: "carried-over") }

  private func model(_ account: String) -> URL {
    root.appending(path: "models").appending(path: Self.fileName(account))
  }

  private func connector(_ id: ConnectorID) -> URL {
    root.appending(path: "connectors").appending(path: Self.fileName(id.rawValue))
  }

  private static func fileName(_ name: String) -> String {
    name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
  }

  private func read(_ url: URL) throws(KeyVaultError) -> Data? {
    do {
      return try Data(contentsOf: url)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return nil
    } catch {
      throw KeyVaultError(reason: error.localizedDescription)
    }
  }

  private func write(_ data: Data?, to url: URL) throws(KeyVaultError) {
    let manager = FileManager.default
    do {
      guard let data else {
        if manager.fileExists(atPath: url.path(percentEncoded: false)) { try manager.removeItem(at: url) }
        return
      }
      for folder in [root, url.deletingLastPathComponent()] {
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path(percentEncoded: false))
      }
      try data.write(to: url, options: .atomic)
      try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
    } catch {
      throw KeyVaultError(reason: error.localizedDescription)
    }
  }
}

/// Why a secret could not be read or kept.
public struct KeyVaultError: Error, Hashable, Sendable {
  public let reason: String

  public init(reason: String) {
    self.reason = reason
  }
}
