import Foundation
import LociModel
import Testing

@testable import LociStore

struct SecretFolderTests {
  struct Former: FormerSecrets {
    let found: FoundSecrets
    func all() -> FoundSecrets { found }
  }

  @Test func secretsAreKeptInFilesOnlyThisUserCanRead() throws {
    try withSecrets { folder, root in
      try folder.save(Data([1, 2, 3]))
      try folder.setKey("sk-model", account: "provider:deepSeek")
      try folder.setSecret(Data("token".utf8), for: ConnectorID("https://mcp.notion.com/mcp"))

      #expect(try folder.load() == Data([1, 2, 3]))
      #expect(try folder.hasKey(account: "provider:deepSeek"))
      #expect(try folder.key(account: "provider:deepSeek") == "sk-model")
      #expect(try folder.secret(for: ConnectorID("https://mcp.notion.com/mcp")) == Data("token".utf8))
      let files = try FileManager.default.subpathsOfDirectory(atPath: root.path(percentEncoded: false))
      for path in files {
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path(percentEncoded: false) + "/" + path)
        let mode = (attributes[.posixPermissions] as? Int) ?? 0
        #expect(mode & 0o077 == 0, "\(path) is open to others")
      }
      #expect(try permissions(of: root) == 0o700)
    }
  }

  @Test func aRemovedSecretIsGone() throws {
    try withSecrets { folder, _ in
      try folder.setKey("sk-model", account: "provider:openAI")
      try folder.setKey(nil, account: "provider:openAI")
      try folder.setSecret(nil, for: ConnectorID("never-saved"))

      #expect(try !folder.hasKey(account: "provider:openAI"))
      #expect(try folder.key(account: "provider:openAI") == nil)
      #expect(try folder.load() == nil)
    }
  }

  @Test func whatTheKeychainHeldIsBroughtOverOnce() throws {
    try withSecrets { folder, _ in
      let notion = ConnectorID("notion")
      let former = Former(
        found: FoundSecrets(
          device: Data([9]), models: ["provider:deepSeek": Data("sk-old".utf8)], connectors: [notion: Data("t".utf8)]))

      try folder.carryOver(from: former)
      try folder.setSecret(nil, for: notion)
      try folder.carryOver(from: former)

      #expect(try folder.load() == Data([9]))
      #expect(try folder.key(account: "provider:deepSeek") == "sk-old")
      #expect(try folder.secret(for: notion) == nil)
    }
  }

  @Test func bringingOverKeepsWhatIsAlreadyInTheFolder() throws {
    try withSecrets { folder, _ in
      try folder.save(Data([1]))

      try folder.carryOver(from: Former(found: FoundSecrets(device: Data([9]))))

      #expect(try folder.load() == Data([1]))
    }
  }

  private func withSecrets(_ body: (SecretFolder, URL) throws -> Void) throws {
    let parent = FileManager.default.temporaryDirectory.appending(path: "loci-secrets-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: parent) }
    let root = parent.appending(path: "secrets")
    try body(SecretFolder(root: root), root)
  }

  private func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
    return (attributes[.posixPermissions] as? Int) ?? 0
  }
}
