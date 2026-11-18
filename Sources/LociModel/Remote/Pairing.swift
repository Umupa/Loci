/// Four digits both Macs derive from the same handshake. Equal codes on both screens mean nobody sits in
/// between.
public struct PairingCode: Hashable, Sendable, CustomStringConvertible {
  /// Always four decimal digits.
  public let digits: String

  /// Takes the value modulo 10 000, padded with leading zeros.
  public init(_ value: UInt16) {
    let number = String(value % 10_000)
    digits = String(repeating: "0", count: 4 - number.count) + number
  }

  public var description: String { digits }
}

/// What the Mac asking to pair sees, in order. The stream ends after `paired` or `failed`; dropping it
/// cancels the pairing on both Macs.
public enum PairingStep: Hashable, Sendable {
  /// Show the code and wait for the other Mac to allow.
  case code(PairingCode)
  case paired(Machine)
  case failed(PairingFailure)
}

/// Another Mac asking to pair with this one, waiting for an answer.
public struct PairingRequest: Hashable, Sendable, Identifiable {
  public let id: EntityID
  public let from: Machine
  public let code: PairingCode

  public init(id: EntityID, from: Machine, code: PairingCode) {
    self.id = id
    self.from = from
    self.code = code
  }
}

public enum PairingFailure: Error, Hashable, Sendable {
  /// The invite link's time ran out.
  case expired
  /// The invite link was already used.
  case used
  /// The other Mac said no, or let the request go unanswered.
  case declined
  /// The other Mac or the relay could not be reached.
  case unreachable
  /// The task waiting for it was cancelled; neither Mac paired.
  case cancelled
}
