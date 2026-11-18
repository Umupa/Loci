import Foundation
import LociModel
import Testing

@testable import LociRemote

struct IssuedInvitesTests {
  static func invite(expires: Int64) throws -> Invite {
    let key = try DeviceKey()
    return try #require(
      Invite(
        id: EntityID(), name: "Mac Studio", model: .studio, address: key.address,
        secret: Data(repeating: 4, count: 32), expires: Timestamp(millisecondsSince1970: expires)))
  }

  @Test func anInviteWorksOnce() throws {
    var issued = IssuedInvites()
    let invite = try Self.invite(expires: 2000)
    issued.issue(invite)

    #expect(try issued.redeem(invite.id, at: Timestamp(millisecondsSince1970: 1000)).get().secret == invite.secret)
    #expect(issued.redeem(invite.id, at: Timestamp(millisecondsSince1970: 1001)) == .failure(.inviteUsed))
  }

  @Test func aReopenedInviteWorksAgain() throws {
    var issued = IssuedInvites()
    let invite = try Self.invite(expires: 2000)
    issued.issue(invite)
    let redeemed = try issued.redeem(invite.id, at: Timestamp(millisecondsSince1970: 1000)).get()

    issued.reopen(redeemed)

    #expect(try issued.redeem(invite.id, at: Timestamp(millisecondsSince1970: 1001)).get() == redeemed)
  }

  @Test func anInviteStopsWorkingWhenItExpires() throws {
    var issued = IssuedInvites()
    let invite = try Self.invite(expires: 2000)
    issued.issue(invite)

    #expect(issued.redeem(invite.id, at: Timestamp(millisecondsSince1970: 2000)) == .failure(.inviteExpired))
  }

  @Test func anInviteThisMacNeverGaveIsRefused() {
    var issued = IssuedInvites()

    #expect(issued.redeem(EntityID(), at: Timestamp(millisecondsSince1970: 0)) == .failure(.inviteUsed))
  }
}

struct NearbyRecordTests {
  @Test func aMacsAnnouncementCarriesWhatIsNeededToDialIt() throws {
    let key = try DeviceKey()
    let mac = NearbyMac(name: "Mac Studio", model: .studio, address: key.address)

    #expect(NearbyRecord.mac(from: NearbyRecord.entries(of: mac)) == mac)
    #expect(NearbyRecord.mac(from: NearbyRecord.entries(of: mac)).map(\.id) == key.machineID)
  }

  @Test func anAnnouncementMissingItsKeyIsIgnored() throws {
    let key = try DeviceKey()
    var entries = NearbyRecord.entries(of: NearbyMac(name: "Mac Studio", model: .studio, address: key.address))
    entries["k"] = nil

    #expect(NearbyRecord.mac(from: entries) == nil)
  }
}
