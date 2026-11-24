import LociModel
import SwiftUI

/// The connected connectors on an ink thread that hangs from the companion's face, each tied to it by a short
/// line. One whose sign-in ran out hangs by a dashed line, gray, with connecting again at its end (CN-S1, CN-S7).
struct ConnectorThread: View {
  let connectors: [Connector]
  let attempts: [ConnectorID: ConnectAttempt]
  /// The ones that just arrived, which drop onto the thread.
  let arriving: Set<ConnectorID>
  /// The one asked for, shown lit for a moment.
  let focused: ConnectorID?
  let away: String?
  let connect: (ConnectorID) -> Void
  let cancel: (ConnectorID) -> Void
  let disconnect: (ConnectorID) -> Void

  static let knot: CGFloat = 22
  static let rowHeight: CGFloat = 62
  /// Where the thread runs, from the left.
  static let threadX: CGFloat = 18
  static let indent: CGFloat = 46

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      LociAvatar(size: Self.knot)
        .padding(.leading, Self.threadX - Self.knot / 2)
        .frame(height: Self.knot, alignment: .top)
      ForEach(Array(connectors.enumerated()), id: \.element.id) { index, connector in
        ConnectedRow(
          connector: connector, attempt: attempts[connector.id], first: index == 0,
          arriving: arriving.contains(connector.id), focused: focused == connector.id, away: away,
          connect: { connect(connector.id) }, cancel: { cancel(connector.id) },
          disconnect: { disconnect(connector.id) })
      }
    }
  }
}

/// One connected connector: its mark, its name and whose account it reads, and what can be done with it.
private struct ConnectedRow: View {
  let connector: Connector
  let attempt: ConnectAttempt?
  let first: Bool
  let arriving: Bool
  let focused: Bool
  let away: String?
  let connect: () -> Void
  let cancel: () -> Void
  let disconnect: () -> Void
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var hovering = false
  @State private var landed = false
  @State private var lit = false

  private var broken: Bool {
    if case .needsReconnecting = connector.status { true } else { false }
  }

  var body: some View {
    HStack(spacing: 14) {
      ConnectorMark(id: connector.id, faded: broken)
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Palette.ink, lineWidth: 1.5)
            .padding(-4)
            .scaleEffect(landed ? 1.35 : 0.9)
            .opacity(arriving && !landed ? 0.9 : 0)
        }
        .offset(y: landed ? 0 : 18)
        .scaleEffect(landed ? 1 : 0.6)
        .opacity(landed ? 1 : 0)
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: connector.name).font(.system(size: 15, weight: .medium)).lineLimit(2)
        account
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      trailing.fixedSize()
    }
    .frame(minHeight: ConnectorThread.rowHeight)
    .padding(.leading, ConnectorThread.indent)
    .padding(.trailing, 8)
    .background(alignment: .topLeading) { thread }
    .background {
      RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.fill).opacity(lit ? 1 : 0)
        .padding(.leading, ConnectorThread.indent - 8)
    }
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .contextMenu { disconnectButton }
    .onAppear(perform: arrive)
  }

  /// Whose account it reads, or the address it reads at; nothing for this Mac's own calendars and reminders.
  @ViewBuilder private var account: some View {
    if connector.source == .local {
      EmptyView()
    } else if let name = connector.account {
      Text(verbatim: name).font(.system(size: 12.5)).foregroundStyle(Palette.inkMuted)
        .lineLimit(1).truncationMode(.middle)
    } else {
      Text(verbatim: connector.server.host() ?? connector.server.absoluteString)
        .font(.system(size: 12).monospaced()).foregroundStyle(Palette.inkFaint)
        .lineLimit(1).truncationMode(.middle)
    }
  }

  @ViewBuilder private var trailing: some View {
    if broken || attempt != nil {
      ConnectControl(attempt: attempt, reconnect: broken, away: away, connect: connect, cancel: cancel)
    } else {
      Menu {
        disconnectButton
      } label: {
        Image(systemName: Symbols.more)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Palette.inkMuted)
          .frame(width: 26, height: 26)
          .background(Circle().fill(Palette.fill))
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .opacity(hovering ? 1 : 0)
      .accessibilityLabel(Text(.loci("connectors.more")))
    }
  }

  private var disconnectButton: some View {
    Button(role: .destructive, action: disconnect) { Text(.loci("connectors.disconnect")) }
      .changesData()
  }

  /// The thread from the one above, or from the face, down to this row, and the tie across to its mark.
  private var thread: some View {
    let half = ConnectorThread.rowHeight / 2
    let x = ConnectorThread.threadX
    let style = StrokeStyle(lineWidth: 1.5, dash: broken ? [3, 3] : [])
    let color = broken ? Palette.inkFaint : Palette.ink.opacity(0.3)
    return ZStack(alignment: .topLeading) {
      Path { path in
        path.move(to: CGPoint(x: x, y: first ? 0 : -half))
        path.addLine(to: CGPoint(x: x, y: half))
      }
      .stroke(color, style: style)
      Path { path in
        path.move(to: CGPoint(x: x, y: half))
        path.addLine(to: CGPoint(x: ConnectorThread.indent - 6, y: half))
      }
      .trim(from: 0, to: landed ? 1 : 0)
      .stroke(color, style: style)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func arrive() {
    guard arriving, !reduceMotion else {
      landed = true
      if focused { light() }
      return
    }
    withAnimation(.spring(duration: 0.7, bounce: 0.45)) { landed = true }
    if focused { light() }
  }

  private func light() {
    lit = true
    withAnimation(.easeOut(duration: 1.6).delay(1.2)) { lit = false }
  }
}
