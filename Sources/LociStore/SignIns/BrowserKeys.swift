import Foundation
import LociModel
import Security

/// Where a browser's cookie password is read from.
public protocol BrowserKeys: Sendable {
  func password(for browser: SignInBrowser) throws(SignInFailure) -> Data
}

/// The login keychain. macOS asks the reader the first time; "Always Allow" lets later launches read it quietly.
public struct LoginKeychain: BrowserKeys {
  public init() {}

  public func password(for browser: SignInBrowser) throws(SignInFailure) -> Data {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: browser.keychainService,
      kSecAttrAccount as String: browser.keychainAccount, kSecReturnData as String: true,
    ]
    var found: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &found)
    switch status {
    case errSecSuccess:
      guard let password = found as? Data else { throw .unreadable }
      return password
    case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
      throw .keyRefused
    default:
      throw .unreadable
    }
  }
}
