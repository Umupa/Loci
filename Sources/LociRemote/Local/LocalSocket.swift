import Foundation
import LociModel
import Network

/// The unix socket the `loci` command reaches the app through. Each connection carries one `LocalCall`
/// and the replies to it, each encoded as JSON. Only this Mac's user can reach it: the folder it
/// is in is theirs alone.
public enum LocalSocket {
  /// Answers calls at `path` until the calling task is cancelled. `answer` sends its replies through the
  /// function it is given. The connection stays until the caller acknowledges a reply or hangs up.
  public static func serve(
    at path: URL,
    answer: @escaping @Sendable (LocalCall, _ reply: @Sendable (LocalReply) async throws -> Void) async -> Void
  ) async throws(LocalSocketError) {
    do {
      let listener = try NetworkListener(using: .parameters { TLV { TCP() } }.localEndpoint(.unix(path: path.path)))
      try await listener.run { connection in
        let call = try JSONDecoder().decode(LocalCall.self, from: try await receive(on: connection))
        await withTaskGroup(of: Void.self) { group in
          group.addTask {
            await answer(call) { reply in try await connection.send(JSONEncoder().encode(reply), type: 0) }
            try? await connection.send(Data([0]), type: endFrame)
          }
          _ = try? await connection.receive()
          group.cancelAll()
        }
      }
    } catch is CancellationError {
      return
    } catch {
      throw .failed(error.localizedDescription)
    }
  }

  /// Sends `call` to the app at `path` and gives the replies to `until` as they come; returns the reply it
  /// accepted. Fails at once when nothing listens there, rather than waiting for something to; once
  /// connected, the app hanging up is the end of the replies, not a failure of the connection.
  public static func call(
    _ call: LocalCall, at path: URL, until accepts: @escaping @Sendable (LocalReply) -> Bool = { _ in true }
  ) async throws(LocalSocketError) -> LocalReply {
    let (troubles, trouble) = AsyncStream.makeStream(of: NWError.self)
    let connection = NetworkConnection(to: .unix(path: path.path), using: .parameters { TLV { TCP() } })
    connection.onStateUpdate { _, state in
      switch state {
      case .waiting(let error), .failed(let error): trouble.yield(error)
      case .ready: trouble.finish()
      default: break
      }
    }
    do {
      return try await withThrowingTaskGroup(of: LocalReply?.self) { group in
        group.addTask {
          try await connection.send(JSONEncoder().encode(call), type: 0)
          while true {
            let reply = try JSONDecoder().decode(LocalReply.self, from: try await receive(on: connection))
            if accepts(reply) {
              try? await connection.send(Data([0]), type: endFrame, lastMessage: true)
              return reply
            }
          }
        }
        group.addTask {
          for await error in troubles { throw error }
          return nil
        }
        defer {
          group.cancelAll()
          trouble.finish()
        }
        while let result = try await group.next() {
          if let reply = result { return reply }
        }
        throw LocalSocketError.closed
      }
    } catch let error as LocalSocketError {
      throw error
    } catch {
      throw Self.failure(error)
    }
  }

  private static let endFrame = 1

  private static func receive(on connection: NetworkConnection<TLV>) async throws -> Data {
    var data = Data()
    while true {
      let frame = try await connection.receive()
      data.append(frame.content)
      switch frame.metadata.type {
      case 0:
        if frame.metadata.isComplete { return data }
      case endFrame:
        throw LocalSocketError.closed
      default:
        throw LocalSocketError.failed("The app sent an invalid local message frame.")
      }
    }
  }

  private static func failure(_ error: any Error) -> LocalSocketError {
    if let error = error as? NWError, case .posix(let code) = error, [.ENOENT, .ECONNREFUSED].contains(code) {
      return .notListening
    }
    return .failed(error.localizedDescription)
  }
}

public enum LocalSocketError: Error, Hashable, Sendable {
  /// Nothing is listening at the path: the app is not running, or it is another data folder's.
  case notListening
  /// The app hung up before it answered.
  case closed
  case failed(String)
}
