import Foundation
import LociModel
import Testing

struct InviteTests {
  static let address = PeerAddress(
    routeToken: Base64URL.encode(Data(repeating: 7, count: 32)), publicKey: Data(repeating: 9, count: 32))!
  static let invite = Invite(
    id: EntityID(canonical: "019a8f1c-87b8-7fed-b346-6f8a7b81a989")!, name: "Mac Studio", model: .studio,
    address: address, secret: Data(repeating: 3, count: 32),
    expires: Timestamp(millisecondsSince1970: 1_763_337_600_123))!

  @Test func aPastedInviteLinkCarriesEverythingToPair() throws {
    let pasted = try #require(Invite(pasted: "  \(Self.invite.link)\n"))

    #expect(pasted == Self.invite)
    #expect(pasted.from.name == "Mac Studio")
    #expect(pasted.from.id == MachineID(publicKey: Self.address.publicKey))
    #expect(Self.invite.link.hasPrefix("loci://pair/"))
  }

  @Test func anythingElseIsNotAnInvite() {
    let link = Self.invite.link
    var changed = Array(link)
    changed[20] = changed[20] == "A" ? "B" : "A"

    #expect(Invite(pasted: "https://example.com") == nil)
    #expect(Invite(pasted: "loci://pair/") == nil)
    #expect(Invite(pasted: String(link.dropLast(12))) == nil)
    #expect(Invite(pasted: link + "=") == nil)
    #expect(Invite(pasted: String(changed)) == nil)
  }

  @Test func anInviteExpiresAtItsTime() {
    #expect(!Self.invite.hasExpired(at: Timestamp(millisecondsSince1970: 1_763_337_600_122)))
    #expect(Self.invite.hasExpired(at: Timestamp(millisecondsSince1970: 1_763_337_600_123)))
  }
}

struct MachineTests {
  @Test func aMachinesIDIsTheFingerprintOfItsKey() {
    let id = MachineID(publicKey: Data(repeating: 9, count: 32))

    #expect(id.fingerprint.count == 32)
    #expect(MachineID(id.fingerprint) == id)
    #expect(MachineID("not hex") == nil)
    #expect(MachineID(id.fingerprint.uppercased()) == nil)
  }

  @Test func aPairingCodeAlwaysHasFourDigits() {
    #expect(PairingCode(7).digits == "0007")
    #expect(PairingCode(10_042).digits == "0042")
    #expect(PairingCode(9999).digits == "9999")
  }

  @Test func aRelayAddressNeedsAWholeTokenAndKey() {
    #expect(PeerAddress(routeToken: "short", publicKey: Data(repeating: 1, count: 32)) == nil)
    #expect(PeerAddress(routeToken: Base64URL.encode(Data(count: 32)), publicKey: Data(count: 31)) == nil)
  }

  @Test func base64URLRoundTripsAndRejectsOtherAlphabets() {
    let bytes = Data((0...255).map(UInt8.init))

    #expect(Base64URL.decode(Base64URL.encode(bytes)) == bytes)
    #expect(Base64URL.decode("ab+c") == nil)
    #expect(Base64URL.decode("abc=") == nil)
  }
}
