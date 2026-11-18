import CryptoKit
import Foundation
import Testing

@testable import LociRemote

/// The handshakes and transport match cacophony's published vectors byte for byte.
struct NoiseVectorTests {
  struct Vector: Decodable {
    let protocolName: String
    let initPrologue: String
    let initStatic: String
    let initEphemeral: String
    let initRemoteStatic: String
    let initPsks: [String]?
    let respStatic: String
    let respEphemeral: String
    let handshakeHash: String
    let messages: [Message]

    struct Message: Decodable {
      let payload: String
      let ciphertext: String
    }
  }

  static func vector(_ name: String) throws -> Vector {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/noise-vectors", withExtension: "json"))
    struct File: Decodable { let vectors: [Vector] }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = try decoder.decode(File.self, from: Data(contentsOf: url))
    return try #require(file.vectors.first { $0.protocolName == name })
  }

  @Test(arguments: [HandshakePattern.ik, .ikpsk2])
  func handshakeAndTransportMatchTheCacophonyVectors(pattern: HandshakePattern) throws {
    let vector = try Self.vector(pattern.name)
    let prologue = Data(hex: vector.initPrologue)
    let psk = vector.initPsks?.first.map(Data.init(hex:))
    let initiatorEphemeral = try key(vector.initEphemeral)
    let responderEphemeral = try key(vector.respEphemeral)
    let responderStatic = try key(vector.respStatic)
    var initiator = Handshake(
      pattern, role: .initiator, prologue: prologue, localStatic: try key(vector.initStatic),
      remoteStatic: responderStatic.publicKey, preSharedKey: psk, makeEphemeral: { initiatorEphemeral })
    var responder = Handshake(
      pattern, role: .responder, prologue: prologue, localStatic: responderStatic, preSharedKey: psk,
      makeEphemeral: { responderEphemeral })

    let first = vector.messages[0]
    #expect(try initiator.write(payload: Data(hex: first.payload)) == Data(hex: first.ciphertext))
    #expect(try responder.read(Data(hex: first.ciphertext)) == Data(hex: first.payload))
    let second = vector.messages[1]
    #expect(try responder.write(payload: Data(hex: second.payload)) == Data(hex: second.ciphertext))
    #expect(try initiator.read(Data(hex: second.ciphertext)) == Data(hex: second.payload))
    #expect(initiator.hash == Data(hex: vector.handshakeHash))
    #expect(responder.hash == initiator.hash)

    var initiatorKeys = try initiator.transport()
    var responderKeys = try responder.transport()
    for (index, message) in vector.messages.enumerated().dropFirst(2) {
      let payload = Data(hex: message.payload)
      let ciphertext = Data(hex: message.ciphertext)
      if index.isMultiple(of: 2) {
        #expect(try initiatorKeys.send.encrypt(payload) == ciphertext)
        #expect(try responderKeys.receive.decrypt(ciphertext) == payload)
      } else {
        #expect(try responderKeys.send.encrypt(payload) == ciphertext)
        #expect(try initiatorKeys.receive.decrypt(ciphertext) == payload)
      }
    }
  }

  @Test func aChangedMessageFailsToDecrypt() throws {
    let responderStatic = Handshake.PrivateKey()
    var initiator = Handshake(
      .ik, role: .initiator, prologue: Data(), localStatic: Handshake.PrivateKey(),
      remoteStatic: responderStatic.publicKey)
    var responder = Handshake(.ik, role: .responder, prologue: Data(), localStatic: responderStatic)
    var message = try initiator.write(payload: Data("hello".utf8))
    message[message.count - 1] ^= 1

    #expect(throws: NoiseError.decryptFailed) { try responder.read(message) }
  }

  @Test func theResponderLearnsWhoIsCallingFromTheFirstMessage() throws {
    let caller = Handshake.PrivateKey()
    let responderStatic = Handshake.PrivateKey()
    var initiator = Handshake(
      .ik, role: .initiator, prologue: Data(), localStatic: caller, remoteStatic: responderStatic.publicKey)
    var responder = Handshake(.ik, role: .responder, prologue: Data(), localStatic: responderStatic)

    _ = try responder.read(try initiator.write())

    #expect(responder.remoteStatic?.rawRepresentation == caller.publicKey.rawRepresentation)
  }

  @Test func differentProloguesNeverAgree() throws {
    let responderStatic = Handshake.PrivateKey()
    var initiator = Handshake(
      .ik, role: .initiator, prologue: Data("loci/1 control".utf8), localStatic: Handshake.PrivateKey(),
      remoteStatic: responderStatic.publicKey)
    var responder = Handshake(.ik, role: .responder, prologue: Data("loci/1 data".utf8), localStatic: responderStatic)

    #expect(throws: NoiseError.decryptFailed) { try responder.read(try initiator.write()) }
  }

  @Test func aWrongPreSharedKeyFailsTheSecondMessage() throws {
    let responderStatic = Handshake.PrivateKey()
    var initiator = Handshake(
      .ikpsk2, role: .initiator, prologue: Data(), localStatic: Handshake.PrivateKey(),
      remoteStatic: responderStatic.publicKey, preSharedKey: Data(repeating: 1, count: 32))
    var responder = Handshake(.ikpsk2, role: .responder, prologue: Data(), localStatic: responderStatic)

    _ = try responder.read(try initiator.write(payload: Data("invite".utf8)))
    responder.providePreSharedKey(Data(repeating: 2, count: 32))

    #expect(throws: NoiseError.decryptFailed) { try initiator.read(try responder.write()) }
  }

  private func key(_ hex: String) throws -> Handshake.PrivateKey {
    try Handshake.PrivateKey(rawRepresentation: Data(hex: hex))
  }
}

extension Data {
  init(hex: String) {
    var bytes: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
      index = next
    }
    self.init(bytes)
  }
}
