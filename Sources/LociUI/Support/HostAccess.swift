import LociModel
import SwiftUI

extension EnvironmentValues {
  /// Where every view gets its data and sends its commands.
  @Entry var host: any LociModel.Host = DeferredHost()
}

/// A host that is not ready yet. Commands and subscriptions wait for it, so the window can open and take
/// input before the storage behind it has started.
public final class DeferredHost: LociModel.Host {
  private let ready = Readiness()

  public init() {}

  /// Hands over the real host; everything waiting goes to it.
  public func resolve(_ host: any LociModel.Host) async {
    await ready.resolve(host)
  }

  public func run<C: Command>(_ command: C) async throws(HostError) -> C.Reply {
    try await ready.host().run(command)
  }

  public func subscribe<S: Subscription>(_ subscription: S) -> AsyncStream<Feed<S.Value>> {
    let (feed, continuation) = AsyncStream.makeStream(of: Feed<S.Value>.self)
    let forwarding = Task { [ready] in
      for await delivered in await ready.host().subscribe(subscription) { continuation.yield(delivered) }
      continuation.finish()
    }
    continuation.onTermination = { _ in forwarding.cancel() }
    return feed
  }

  public func upload(_ file: LocalFile) async throws(HostError) -> Upload {
    try await ready.host().upload(file)
  }

  public func localFile(_ place: LocalPlace) async -> LocalFile? {
    await ready.host().localFile(place)
  }

  public func modelSettingsAccess() async -> (any ModelSettingsAccess)? {
    await ready.host().modelSettingsAccess()
  }

  private actor Readiness {
    private var resolved: (any LociModel.Host)?
    private var waiting: [CheckedContinuation<any LociModel.Host, Never>] = []

    func resolve(_ host: any LociModel.Host) {
      resolved = host
      for waiter in waiting { waiter.resume(returning: host) }
      waiting = []
    }

    func host() async -> any LociModel.Host {
      if let resolved { return resolved }
      return await withCheckedContinuation { waiting.append($0) }
    }
  }
}

extension View {
  /// Keeps `feed` current with the subscription for as long as the view is shown.
  func subscribing<S: Subscription>(_ subscription: S, into feed: Binding<Feed<S.Value>?>) -> some View {
    modifier(Subscribing(subscription: subscription, feed: feed))
  }
}

private struct Subscribing<S: Subscription>: ViewModifier {
  @Environment(\.host) private var host
  let subscription: S
  @Binding var feed: Feed<S.Value>?

  func body(content: Content) -> some View {
    content.task(id: subscription) {
      for await delivered in host.subscribe(subscription) { feed = delivered }
    }
  }
}

extension Feed {
  var value: Value? {
    if case .value(let value) = self { return value }
    return nil
  }
}
