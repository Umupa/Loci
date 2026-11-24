import LociModel
import SwiftUI

/// The services connected to the companion, on an ink thread, over a card of what can still be connected,
/// ending in a field for any MCP address. The page is ink and gray only, no amber (CN-S1, CN-S2, CN-S7, CN-S8).
struct ConnectorsTab: View {
  /// The connector to show lit, as when a reply asked to open it.
  var focused: ConnectorID?
  @Environment(\.host) private var host
  @Environment(\.showFailure) private var showFailure
  @Environment(\.openInBrowser) private var openInBrowser
  @Environment(\.browser) private var browser
  @Environment(\.openPlace) private var openPlace
  @Environment(\.machineChoice) private var machineChoice
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var connectors: Feed<Connectors>?
  @State private var known: Set<ConnectorID>?
  @State private var arriving: Set<ConnectorID> = []

  /// The name of the Mac the companion lives on, when this window shows it from another one.
  private var away: String? {
    machineChoice?.link == nil ? nil : machineChoice?.shown.name
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      if let connectors = connectors?.value {
        if !connectors.connected.isEmpty {
          ConnectorThread(
            connectors: connectors.connected, attempts: connectors.attempts, arriving: arriving, focused: focused,
            away: away, connect: connect, cancel: cancel, disconnect: disconnect)
        }
        OfferCard(
          offers: connectors.available, attempts: connectors.attempts, away: away, connect: connect, cancel: cancel,
          add: add)
      }
    }
    .frame(maxWidth: 640, alignment: .leading)
    .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.1), value: connectors?.value)
    .subscribing(WatchConnectors(), into: $connectors)
    .onChange(of: connectors?.value?.connected.map(\.id)) { _, ids in arrived(ids ?? []) }
  }

  /// Notes which connectors are new since the page last looked, so they drop onto the thread.
  private func arrived(_ ids: [ConnectorID]) {
    let now = Set(ids)
    if let known { arriving = now.subtracting(known) }
    known = now
  }

  private func connect(_ id: ConnectorID) {
    run(Connect(id), then: follow)
  }

  private func add(_ address: URL) {
    run(AddMCPServer(address), then: follow)
  }

  /// Opens the page a connection asks for: an OAuth sign-in in the default browser, a website's sign-in in a
  /// new tab of the built-in browser, which the window turns to.
  private func follow(_ authorization: Authorization) {
    authorization.follow(
      inBrowser: { openInBrowser($0) },
      inBuiltInBrowser: { page in
        browser?.open(page)
        openPlace(.browser)
      })
  }

  private func cancel(_ id: ConnectorID) {
    run(CancelConnecting(id)) { _ in }
  }

  private func disconnect(_ id: ConnectorID) {
    run(Disconnect(id)) { _ in }
  }

  private func run<C: Command>(_ command: C, then: @escaping @MainActor (C.Reply) -> Void) {
    Task {
      do throws(HostError) {
        then(try await host.run(command))
      } catch {
        showFailure(error)
      }
    }
  }
}

/// What can still be connected, in the order the host gives, then a field for an MCP address.
private struct OfferCard: View {
  let offers: [ConnectorOffer]
  let attempts: [ConnectorID: ConnectAttempt]
  let away: String?
  let connect: (ConnectorID) -> Void
  let cancel: (ConnectorID) -> Void
  let add: (URL) -> Void

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    VStack(spacing: 0) {
      ForEach(Array(offers.enumerated()), id: \.element.id) { index, offer in
        HStack(spacing: 14) {
          ConnectorMark(id: offer.id, size: 30)
          Text(verbatim: offer.name).font(.system(size: 15, weight: .medium)).lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
          ConnectControl(
            attempt: attempts[offer.id], away: away, connect: { connect(offer.id) }, cancel: { cancel(offer.id) }
          )
          .fixedSize()
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(minHeight: 58)
        .rule(index > 0)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
      if away == nil {
        AddressRow(add: add).rule(!offers.isEmpty)
      }
    }
    .background(Palette.surface)
    .clipShape(shape)
    .cardShadow(shape)
  }
}

/// A field for any MCP address, connected the same way as the ones listed.
private struct AddressRow: View {
  let add: (URL) -> Void
  @State private var text = ""

  private var address: URL? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let url = URL(string: trimmed), url.scheme == "https", url.host()?.isEmpty == false else { return nil }
    return url
  }

  var body: some View {
    HStack(spacing: 14) {
      ConnectorMark(id: ConnectorID(""), size: 30)
      TextField(text: $text, prompt: Text(verbatim: "https://")) { Text(.loci("connectors.address")) }
        .textFieldStyle(.plain)
        .font(.system(size: 13).monospaced())
        .onSubmit(submit)
      Button(action: submit) { Text(.loci("connectors.connect")) }
        .buttonStyle(InkButtonStyle(look: address == nil ? .wash : .solid))
        .disabled(address == nil)
        .fixedSize()
        .changesData()
    }
    .padding(.leading, 16)
    .padding(.trailing, 14)
    .frame(minHeight: 58)
  }

  private func submit() {
    guard let address else { return }
    add(address)
    text = ""
  }
}

extension Authorization {
  /// Hands the page to open to the browser it is for; nothing for a connector that is ready.
  func follow(inBrowser: (URL) -> Void, inBuiltInBrowser: (URL) -> Void) {
    switch self {
    case .open(let page): inBrowser(page)
    case .openInBuiltInBrowser(let page): inBuiltInBrowser(page)
    case .connected: break
    }
  }
}
