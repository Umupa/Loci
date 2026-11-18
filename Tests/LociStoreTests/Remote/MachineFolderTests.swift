import Foundation
import LociModel
import LociStore
import Testing

struct MachineFolderTests {
  static func withFolder(_ body: (MachineFolder) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "loci-machines-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try body(MachineFolder(root: root))
  }

  static func peer(_ name: String, key byte: UInt8) -> PairedPeer {
    let address = PeerAddress(
      routeToken: String(repeating: "A", count: 43), publicKey: Data(repeating: byte, count: 32))!
    return PairedPeer(
      machine: Machine(id: MachineID(publicKey: address.publicKey), name: name, model: .studio), address: address,
      pairedAt: Timestamp(millisecondsSince1970: 1_763_337_600_123))
  }

  @Test func theRosterSurvivesARestart() throws {
    try Self.withFolder { folder in
      let peers = [Self.peer("Mac Studio", key: 1), Self.peer("iMac", key: 2)]
      try folder.saveRoster(peers)

      #expect(MachineFolder(root: folder.root).roster() == peers)
    }
  }

  @Test func withoutARosterNoMacIsPaired() throws {
    try Self.withFolder { folder in
      #expect(folder.roster().isEmpty)
    }
  }

  @Test func whatWasSeenIsKeptPerMacAndForgottenWithIt() throws {
    try Self.withFolder { folder in
      let studio = Self.peer("Mac Studio", key: 1).machine.id
      let imac = Self.peer("iMac", key: 2).machine.id
      try folder.cache(Data("studio".utf8), as: "item.list", request: Data("{}".utf8), on: studio)
      try folder.cache(Data("imac".utf8), as: "item.list", request: Data("{}".utf8), on: imac)

      #expect(folder.cached("item.list", request: Data("{}".utf8), on: studio) == Data("studio".utf8))
      #expect(folder.cached("item.list", request: Data("{\"x\":1}".utf8), on: studio) == nil)
      try folder.forget(studio)
      #expect(folder.cached("item.list", request: Data("{}".utf8), on: studio) == nil)
      #expect(folder.cached("item.list", request: Data("{}".utf8), on: imac) == Data("imac".utf8))
    }
  }

  @Test func anUploadArrivesInPiecesUnderItsOwnName() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "loci-machines-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = MachineFolder(root: root)
    let upload = try folder.receiveUpload(named: "../talk.mov", id: EntityID())
    try upload.append(Data("abc".utf8))
    try upload.append(Data("def".utf8))
    let file = try upload.finish()

    #expect(file.lastPathComponent == "talk.mov")
    #expect(try Data(contentsOf: file) == Data("abcdef".utf8))
    var pieces: [Data] = []
    for try await piece in try MachineFolder.pieces(of: file, size: 4) { pieces.append(piece) }
    #expect(pieces == [Data("abcd".utf8), Data("ef".utf8)])
  }
}
