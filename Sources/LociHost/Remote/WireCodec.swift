import Foundation
import LociModel
import LociRemote

/// Commands and subscriptions to and from the bytes of a session. A reply of type `Data` travels as the
/// bytes themselves; everything else as JSON with sorted keys, so equal requests are equal bytes.
enum WireCodec {
  static func encode(_ value: some Encodable) throws(HostError) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    do {
      return try encoder.encode(value)
    } catch {
      throw .invalidRequest("cannot encode \(type(of: value)): \(error)")
    }
  }

  static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws(HostError) -> Value {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw .invalidRequest("cannot decode \(type): \(error)")
    }
  }

  static func replyBody<Reply: Encodable>(_ reply: Reply) throws(HostError) -> Data {
    if let bytes = reply as? Data { return bytes }
    return try encode(reply)
  }

  static func reply<Reply: Decodable>(_ type: Reply.Type, from body: Data) throws(HostError) -> Reply {
    if let bytes = body as? Reply, Reply.self == Data.self { return bytes }
    return try decode(type, from: body)
  }

  /// Runs a command named on the wire against a host, for the Mac being opened.
  static func run(_ name: String, body: Data, on host: any LociModel.Host) async throws(HostError) -> Data {
    guard let route = Wire.commands.first(where: { $0.name == name }) else {
      throw .invalidRequest("\(name) cannot be used from another Mac")
    }
    return try await run(route.command, body: body, on: host)
  }

  static func run<C: Command>(_ type: C.Type, body: Data, on host: any LociModel.Host) async throws(HostError)
    -> Data
  {
    let command = try decode(type, from: body)
    return try replyBody(try await host.run(command))
  }

  /// A subscription named on the wire, as a stream of its feeds in JSON.
  static func feeds(_ name: String, body: Data, on host: any LociModel.Host) throws(HostError) -> AsyncStream<JSONValue>
  {
    guard let type = Wire.subscriptions.first(where: { $0.name == name }) else {
      throw .invalidRequest("\(name) cannot be followed from another Mac")
    }
    return try feeds(type, body: body, on: host)
  }

  private static func feeds<S: Subscription>(_ type: S.Type, body: Data, on host: any LociModel.Host) throws(HostError)
    -> AsyncStream<JSONValue>
  {
    let subscription = try decode(type, from: body)
    let source = host.subscribe(subscription)
    return AsyncStream { continuation in
      let forwarding = Task {
        for await feed in source {
          if let json = try? JSONValue(encoding: feed) { continuation.yield(json) }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in forwarding.cancel() }
    }
  }
}
