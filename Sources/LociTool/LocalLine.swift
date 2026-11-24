import Foundation
import LociModel
import LociRemote

/// Carries one call to the app and brings back the reply. Tests replace it.
protocol LocalLine: Sendable {
  /// The first value `accepts` takes; a failure the app answers with is thrown.
  func send(_ request: LocalCall.Request, until accepts: @escaping @Sendable (Data) -> Bool) async throws(Failure)
    -> Data
}

extension LocalLine {
  func send(_ request: LocalCall.Request) async throws(Failure) -> Data {
    try await send(request) { _ in true }
  }

  func run<C: Command>(_ command: C) async throws(Failure) -> Data {
    try await send(.command(name: C.name, body: try Failure.encoding(command)))
  }
}

/// The socket the app listens on, for an agent in `session`.
struct SocketLine: LocalLine {
  let socket: URL
  let session: LocalSession?

  func send(_ request: LocalCall.Request, until accepts: @escaping @Sendable (Data) -> Bool) async throws(Failure)
    -> Data
  {
    let call = LocalCall(session: session, request: request)
    let reply: LocalReply
    do {
      reply = try await LocalSocket.call(call, at: socket) { reply in
        switch reply {
        case .value(let data): accepts(data)
        case .failed: true
        }
      }
    } catch {
      throw .socket(error)
    }
    switch reply {
    case .value(let data): return data
    case .failed(let error): throw .host(error)
    }
  }
}

/// Why a command did not work, in words that say what to do about it.
enum Failure: Error, Hashable {
  case host(HostError)
  case socket(LocalSocketError)
  /// No socket to reach the app through: not run by Loci.
  case outsideLoci
  case file(String)
  case unreadable(String)

  var message: String {
    switch self {
    case .host(.notFound(let what)):
      "Nothing in the library is \(what). Find ids with `loci search <words>`."
    case .host(.alreadyExists(let id)): "That is already in the library as \(id)."
    case .host(.invalidFile(let problem)): "\(problem.path) cannot be used: \(problem.reason)"
    case .host(.invalidRequest(let reason)): reason
    case .host(.storage(let reason)): "The library could not be written: \(reason)"
    case .host(.offline): "The Mac with the library cannot be reached."
    case .host(.olderMac): "The Mac with the library runs an older Loci that cannot do this."
    case .socket(.notListening):
      "Loci is not running, or this is not the Loci that started you. The person needs to open Loci."
    case .socket(.closed): "Loci stopped before it answered. Try again."
    case .socket(.failed(let reason)): "Loci could not be reached: \(reason)"
    case .outsideLoci:
      "\(LocalCall.socketVariable) is not set: loci works only in a session Loci started."
    case .file(let reason): reason
    case .unreadable(let reason): "Loci answered in a way this loci does not understand: \(reason)"
    }
  }

  static func encoding(_ value: some Encodable) throws(Failure) -> Data {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      return try encoder.encode(value)
    } catch {
      throw .unreadable(String(describing: error))
    }
  }

  static func decoding<Value: Decodable>(_ type: Value.Type, from data: Data) throws(Failure) -> Value {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw .unreadable(String(describing: error))
    }
  }
}
