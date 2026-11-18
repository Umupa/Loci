import Foundation
import LociModel

/// One message of a session between two Macs, inside the encrypted channel. The calling Mac sends calls,
/// subscriptions and uploads; the Mac being opened answers them by id.
///
/// Encoded as `[kind][id: 4 bytes big-endian][fields]`; a name is `[length: 2 bytes][UTF-8]`, and a body is
/// the rest of the message, so bytes travel without base64.
public enum Frame: Hashable, Sendable {
  case call(id: UInt32, name: String, body: Data)
  /// The reply's JSON, or the bytes themselves when the reply is `Data`.
  case reply(id: UInt32, body: Data)
  case failure(id: UInt32, HostError)
  case cancel(id: UInt32)
  case subscribe(id: UInt32, name: String, body: Data)
  /// The whole `Feed` as JSON: first, and again whenever a delta could not be applied.
  case feed(id: UInt32, body: Data)
  /// A `JSONDelta` from the last feed to the new one.
  case delta(id: UInt32, body: Data)
  case unsubscribe(id: UInt32)
  /// Asks for the whole feed again, after a delta did not fit.
  case resend(id: UInt32)
  case uploadPart(id: UInt32, bytes: Data)
  /// The file is complete; the reply is the `Upload` that names it.
  case uploadEnd(id: UInt32, fileName: String)
  /// The sender removed the receiver from its roster.
  case unpaired

  private enum Kind: UInt8 {
    case call = 1
    case reply
    case failure
    case cancel
    case subscribe
    case feed
    case delta
    case unsubscribe
    case resend
    case uploadPart
    case uploadEnd
    case unpaired
  }

  public var encoded: Data {
    switch self {
    case .call(let id, let name, let body): Self.pack(.call, id, name: name, body)
    case .reply(let id, let body): Self.pack(.reply, id, body)
    case .failure(let id, let error): Self.pack(.failure, id, (try? JSONEncoder().encode(error)) ?? Data())
    case .cancel(let id): Self.pack(.cancel, id)
    case .subscribe(let id, let name, let body): Self.pack(.subscribe, id, name: name, body)
    case .feed(let id, let body): Self.pack(.feed, id, body)
    case .delta(let id, let body): Self.pack(.delta, id, body)
    case .unsubscribe(let id): Self.pack(.unsubscribe, id)
    case .resend(let id): Self.pack(.resend, id)
    case .uploadPart(let id, let bytes): Self.pack(.uploadPart, id, bytes)
    case .uploadEnd(let id, let fileName): Self.pack(.uploadEnd, id, name: fileName)
    case .unpaired: Self.pack(.unpaired, 0)
    }
  }

  public init?(_ data: Data) {
    let bytes = [UInt8](data)
    guard bytes.count >= 5, let kind = Kind(rawValue: bytes[0]) else { return nil }
    let id = bytes[1..<5].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    var rest = Data(bytes[5...])
    switch kind {
    case .call, .subscribe, .uploadEnd:
      guard rest.count >= 2 else { return nil }
      let length = Int(rest[rest.startIndex]) << 8 | Int(rest[rest.startIndex + 1])
      guard rest.count >= 2 + length else { return nil }
      let name = String(decoding: rest.dropFirst(2).prefix(length), as: UTF8.self)
      rest = Data(rest.dropFirst(2 + length))
      switch kind {
      case .call: self = .call(id: id, name: name, body: rest)
      case .subscribe: self = .subscribe(id: id, name: name, body: rest)
      default: self = .uploadEnd(id: id, fileName: name)
      }
    case .reply: self = .reply(id: id, body: rest)
    case .failure:
      guard let error = try? JSONDecoder().decode(HostError.self, from: rest) else { return nil }
      self = .failure(id: id, error)
    case .cancel: self = .cancel(id: id)
    case .feed: self = .feed(id: id, body: rest)
    case .delta: self = .delta(id: id, body: rest)
    case .unsubscribe: self = .unsubscribe(id: id)
    case .resend: self = .resend(id: id)
    case .uploadPart: self = .uploadPart(id: id, bytes: rest)
    case .unpaired: self = .unpaired
    }
  }

  private static func pack(_ kind: Kind, _ id: UInt32, name: String? = nil, _ body: Data = Data()) -> Data {
    var data = Data([kind.rawValue])
    data.append(contentsOf: withUnsafeBytes(of: id.bigEndian) { Array($0) })
    if let name {
      let utf8 = Array(name.utf8.prefix(Int(UInt16.max)))
      data.append(contentsOf: [UInt8(utf8.count >> 8), UInt8(utf8.count & 0xFF)] + utf8)
    }
    return data + body
  }
}
