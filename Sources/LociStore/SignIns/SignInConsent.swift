import Foundation
import LociModel

/// The reader's answer about other browsers' sign-ins. It belongs to this Mac, so it is kept in Application
/// Support rather than the Loci folder another Mac can open.
public enum SignInConsent: Hashable, Codable, Sendable {
  case using(SignInBrowser)
  case declined
}

extension Support {
  var signIns: URL { root.appending(path: "sign-ins.json") }

  /// `nil` until the reader has answered.
  public func signInConsent() -> SignInConsent? {
    guard let data = try? Data(contentsOf: signIns) else { return nil }
    return try? JSONDecoder().decode(SignInConsent.self, from: data)
  }

  public func save(_ consent: SignInConsent) throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Formats.document(consent).write(to: signIns, options: .atomic)
  }
}
