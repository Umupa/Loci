import Foundation
import LociStore
import os

/// This Mac's secrets: files in `secrets` under the app's support folder, with what an earlier Loci kept in the
/// login keychain brought over the first time.
public struct Secrets: Sendable {
  let folder: SecretFolder

  private static let log = Logger(subsystem: "com.loci.native.dev", category: "secrets")

  public static func onThisMac(support: URL) -> Secrets {
    let folder = SecretFolder(root: support.appending(path: "secrets", directoryHint: .isDirectory))
    do {
      try folder.carryOver(from: FormerKeychain())
    } catch {
      log.error("could not bring the keychain's secrets over: \(error.reason, privacy: .public)")
    }
    return Secrets(folder: folder)
  }
}
