import Foundation

/// The frames of alma-relay's agent socket (docs/PROTOCOL.md in alma-relay) that Loci uses, both ways.
/// JSON text frames and, from protocol 2, binary frames `[kind][idLen][id][payload]`.
enum AgentFrame: Hashable, Sendable {
  case register(tokenHash: String, key: String?, proto: Int)
  /// `proto` is absent in protocol 1; `window` comes with protocol 3.
  case registered(proto: Int, window: Int?)
  case error(String)
  case httpRequest(id: String)
  case httpResponse(id: String, status: Int)
  case httpEnd(id: String)
  case socketOpen(id: String, path: String)
  case socketOpened(id: String)
  case socketError(id: String, message: String)
  case socketMessage(id: String, SocketMessage)
  case socketClose(id: String, code: Int?)
  case ack(id: String, bytes: Int)
  /// Frames Loci has no use for, such as request bodies and push results.
  case ignored

  enum BinaryKind: UInt8 {
    case responseChunk = 1
    case requestBody = 2
    case socketBinary = 3
    case socketText = 4
  }

  /// The relay's frame as received. Malformed frames are `nil`.
  init?(_ message: SocketMessage) {
    switch message {
    case .text(let text): self.init(json: Data(text.utf8))
    case .binary(let data): self.init(binary: data)
    }
  }

  /// The frame to send for this protocol: socket messages go as binary frames from protocol 2.
  func encoded(proto: Int) -> SocketMessage {
    if case .socketMessage(let id, let message) = self, proto >= 2 {
      switch message {
      case .text(let text): return .binary(Self.binary(.socketText, id: id, payload: Data(text.utf8)))
      case .binary(let data): return .binary(Self.binary(.socketBinary, id: id, payload: data))
      }
    }
    return .text(String(decoding: (try? JSONSerialization.data(withJSONObject: json)) ?? Data(), as: UTF8.self))
  }

  private var json: [String: Any] {
    switch self {
    case .register(let hash, let key, let proto):
      var frame: [String: Any] = ["t": "register", "tokenHash": hash, "proto": proto, "name": "Loci"]
      if let key { frame["key"] = key }
      return frame
    case .registered(let proto, let window):
      var frame: [String: Any] = ["t": "registered", "proto": proto]
      if let window { frame["window"] = window }
      return frame
    case .error(let message): return ["t": "error", "message": message]
    case .httpRequest(let id): return ["t": "hreq", "id": id, "method": "GET", "path": "/", "headers": [:]]
    case .httpResponse(let id, let status): return ["t": "hres", "id": id, "status": status, "headers": [:]]
    case .httpEnd(let id): return ["t": "hend", "id": id]
    case .socketOpen(let id, let path): return ["t": "wopen", "id": id, "path": path]
    case .socketOpened(let id): return ["t": "wopened", "id": id]
    case .socketError(let id, let message): return ["t": "werr", "id": id, "message": message]
    case .socketMessage(let id, .text(let text)): return ["t": "wmsg", "id": id, "s": text]
    case .socketMessage(let id, .binary(let data)): return ["t": "wmsg", "id": id, "b": data.base64EncodedString()]
    case .socketClose(let id, let code):
      var frame: [String: Any] = ["t": "wclose", "id": id]
      if let code { frame["code"] = code }
      return frame
    case .ack(let id, let bytes): return ["t": "ack", "id": id, "n": bytes]
    case .ignored: return [:]
    }
  }

  private init?(json data: Data) {
    guard let frame = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let type = frame["t"] as? String
    else { return nil }
    let id = frame["id"] as? String
    switch (type, id) {
    case ("register", _):
      guard let hash = frame["tokenHash"] as? String else { return nil }
      self = .register(tokenHash: hash, key: frame["key"] as? String, proto: frame["proto"] as? Int ?? 1)
    case ("registered", _): self = .registered(proto: frame["proto"] as? Int ?? 1, window: frame["window"] as? Int)
    case ("error", _): self = .error(frame["message"] as? String ?? "")
    case ("hreq", let id?): self = .httpRequest(id: id)
    case ("hres", let id?): self = .httpResponse(id: id, status: frame["status"] as? Int ?? 0)
    case ("hend", let id?): self = .httpEnd(id: id)
    case ("wopen", let id?): self = .socketOpen(id: id, path: frame["path"] as? String ?? "/")
    case ("wopened", let id?): self = .socketOpened(id: id)
    case ("werr", let id?): self = .socketError(id: id, message: frame["message"] as? String ?? "")
    case ("wclose", let id?): self = .socketClose(id: id, code: frame["code"] as? Int)
    case ("ack", let id?): self = .ack(id: id, bytes: frame["n"] as? Int ?? 0)
    case ("wmsg", let id?):
      if let text = frame["s"] as? String {
        self = .socketMessage(id: id, .text(text))
      } else if let encoded = frame["b"] as? String, let data = Data(base64Encoded: encoded) {
        self = .socketMessage(id: id, .binary(data))
      } else {
        return nil
      }
    default: self = .ignored
    }
  }

  private init?(binary data: Data) {
    let bytes = [UInt8](data)
    guard bytes.count >= 2, bytes.count >= 2 + Int(bytes[1]) else { return nil }
    let idEnd = 2 + Int(bytes[1])
    guard let id = String(bytes: bytes[2..<idEnd], encoding: .utf8) else { return nil }
    let payload = Data(bytes[idEnd...])
    switch BinaryKind(rawValue: bytes[0]) {
    case .socketBinary: self = .socketMessage(id: id, .binary(payload))
    case .socketText: self = .socketMessage(id: id, .text(String(decoding: payload, as: UTF8.self)))
    case .responseChunk, .requestBody, nil: self = .ignored
    }
  }

  static func binary(_ kind: BinaryKind, id: String, payload: Data) -> Data {
    let idBytes = Array(id.utf8.prefix(255))
    return Data([kind.rawValue, UInt8(idBytes.count)] + idBytes) + payload
  }
}
