import Foundation
import LociModel

/// The invites this Mac gave out and has not yet seen used. Each works once, until it expires; one that is
/// not here (used, expired and forgotten, or from before the app restarted) is refused as used.
public struct IssuedInvites: Sendable {
  /// What this Mac remembers of an invite it gave out.
  public struct Issued: Hashable, Sendable {
    public let id: EntityID
    public let secret: Data
    public let expires: Timestamp
  }

  private var open: [EntityID: Issued] = [:]

  public init() {}

  public mutating func issue(_ invite: Invite) {
    open[invite.id] = Issued(id: invite.id, secret: invite.secret, expires: invite.expires)
  }

  /// The invite, for its secret, or why it no longer works. Either way it cannot be used again, unless it
  /// is reopened.
  public mutating func redeem(_ id: EntityID, at now: Timestamp) -> Result<Issued, Refusal> {
    open = open.filter { $0.value.expires > now || $0.key == id }
    guard let invite = open.removeValue(forKey: id) else { return .failure(.inviteUsed) }
    return now < invite.expires ? .success(invite) : .failure(.inviteExpired)
  }

  /// Makes a redeemed invite usable again, for a pairing that was abandoned before it finished.
  public mutating func reopen(_ invite: Issued) {
    open[invite.id] = invite
  }
}
