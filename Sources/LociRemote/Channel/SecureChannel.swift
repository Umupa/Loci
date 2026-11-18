import Foundation

public enum ChannelError: Error, Hashable, Sendable {
  case socket(SocketError)
  case noise(NoiseError)
  /// The other side sent something that is not part of the protocol.
  case malformed
}

/// Messages of any size over a socket, each one encrypted with the session's transport keys. A message
/// larger than one Noise message goes as several, each prefixed with whether more follow, and messages
/// are sent strictly in order, since every one advances the nonce.
public actor SecureChannel {
  private let socket: any MessageSocket
  private var keys: TransportKeys
  private var lastSend: Task<Void, Never>?

  static let chunk = CipherState.maximumMessage - CipherState.tagLength - 1

  init(socket: any MessageSocket, keys: TransportKeys) {
    self.socket = socket
    self.keys = keys
  }

  public func send(_ message: Data) async throws(ChannelError) {
    let previous = lastSend
    let writing = Task { () -> ChannelError? in
      await previous?.value
      return await self.write(message)
    }
    lastSend = Task { _ = await writing.value }
    if let failure = await writing.value { throw failure }
  }

  private func write(_ message: Data) async -> ChannelError? {
    var offset = message.startIndex
    repeat {
      let end = min(offset + Self.chunk, message.endIndex)
      let more: UInt8 = end < message.endIndex ? 1 : 0
      do {
        let sealed = try keys.send.encrypt(Data([more]) + message[offset..<end])
        try await socket.send(.binary(sealed))
      } catch let error as NoiseError {
        return .noise(error)
      } catch let error as SocketError {
        return .socket(error)
      } catch {
        return .malformed
      }
      offset = end
    } while offset < message.endIndex
    return nil
  }

  /// The next whole message. Throws once the socket is closed.
  public func receive() async throws(ChannelError) -> Data {
    var message = Data()
    while true {
      let sealed: Data
      do {
        guard case .binary(let data) = try await socket.receive() else { throw ChannelError.malformed }
        sealed = data
      } catch let error as SocketError {
        throw .socket(error)
      } catch {
        throw .malformed
      }
      let opened: Data
      do {
        opened = try keys.receive.decrypt(sealed)
      } catch {
        throw .noise(error)
      }
      guard let more = opened.first else { throw .malformed }
      message += opened.dropFirst()
      if more == 0 { return message }
    }
  }

  public func close() async {
    await socket.close(code: 1000)
  }
}
