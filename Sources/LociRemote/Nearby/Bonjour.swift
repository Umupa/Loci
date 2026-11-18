import Foundation
import LociModel
import Network
import os

/// Finding Macs on the same network, and being found.
public protocol NearbyDiscovery: Sendable {
  /// Announces this Mac until the calling task is cancelled.
  func advertise(_ mac: NearbyMac) async
  /// The Macs announcing themselves, again whenever the list changes, for as long as the stream is held.
  func browse() -> AsyncStream<[NearbyMac]>
}

/// Bonjour through the Network framework. The listener exists only to carry the announcement: Loci never
/// connects to another Mac directly, so every connection to it is closed at once.
public struct BonjourDiscovery: NearbyDiscovery {
  private static let log = Logger(subsystem: "com.loci.native.dev", category: "nearby")

  public init() {}

  public func advertise(_ mac: NearbyMac) async {
    do {
      let listener = try NetworkListener(
        for: .bonjour(
          name: mac.name, type: NearbyRecord.serviceType, txtRecord: NWTXTRecord(NearbyRecord.entries(of: mac)))
      ) {
        TCP()
      }
      try await listener.run { _ in }
    } catch {
      Self.log.error("could not announce this Mac: \(error.localizedDescription, privacy: .public)")
    }
  }

  public func browse() -> AsyncStream<[NearbyMac]> {
    let (macs, continuation) = AsyncStream.makeStream(of: [NearbyMac].self, bufferingPolicy: .bufferingNewest(1))
    let browsing = Task {
      let browser = NetworkBrowser(for: .bonjour(NearbyRecord.serviceType, includeTxtRecord: true))
      do {
        try await browser.run { endpoints in
          continuation.yield(endpoints.compactMap { NearbyRecord.mac(from: $0.txtRecord.dictionary) })
        }
      } catch {
        Self.log.error("could not look for nearby Macs: \(error.localizedDescription, privacy: .public)")
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in browsing.cancel() }
    return macs
  }
}
