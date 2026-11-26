import AppKit
import LociModel
import SwiftUI

/// A connector's icon on its tile.
struct ConnectorMark: View {
  let id: ConnectorID
  var size: CGFloat = 34
  /// Gray and faded, for one whose sign-in ran out.
  var faded = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
    shape.fill(Palette.surface)
      .overlay(shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
      .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
      .overlay { ConnectorArt(id: id, size: size * 0.64) }
      .frame(width: size, height: size)
      .saturation(faded ? 0 : 1)
      .opacity(faded ? 0.55 : 1)
      .accessibilityHidden(true)
  }
}

/// The icon shared by connector rows and panel sources.
struct ConnectorArt: View {
  let id: ConnectorID
  let size: CGFloat
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    Group {
      if let art = MarkArt.connector(id, in: scheme) {
        Image(nsImage: art).renderingMode(.original).resizable().scaledToFit()
      } else {
        Image(systemName: fallback).resizable().scaledToFit().fontWeight(.medium)
          .foregroundStyle(Palette.inkMuted).padding(2)
      }
    }
    .frame(width: size, height: size)
  }

  private var fallback: String {
    switch id.rawValue {
    case "calendar": "calendar"
    case "reminders": "checklist"
    default: Symbols.link
    }
  }
}

/// What sits at the end of a connector's row: connecting, waiting for the browser, trying again after a
/// failure, or, on another Mac, the name of the Mac to do it on.
struct ConnectControl: View {
  let attempt: ConnectAttempt?
  /// Its sign-in ran out: connecting again is the one thing to do, so the button is solid.
  var reconnect = false
  /// The Mac the companion lives on, when this window shows it from another one.
  let away: String?
  let connect: () -> Void
  let cancel: () -> Void

  var body: some View {
    if let away {
      AwayPill(mac: away)
    } else if case .waiting(let until) = attempt {
      WaitingRing(until: until.date, cancel: cancel)
    } else if case .failed(let reason) = attempt {
      Button(action: connect) { Text(.loci("connectors.retry")) }
        .buttonStyle(InkButtonStyle(look: .failure))
        .help(Text(verbatim: reason))
        .changesData()
    } else {
      Button(action: connect) { Text(.loci(reconnect ? "connectors.reconnect" : "connectors.connect")) }
        .buttonStyle(InkButtonStyle(look: reconnect ? .solid : .wash))
        .changesData()
    }
  }
}

/// A ring that drains while the browser has the sign-in, ten minutes at most; pointing at it offers to stop.
struct WaitingRing: View {
  let until: Date
  let cancel: () -> Void
  @Environment(\.fixedNow) private var fixedNow
  @State private var hovering = false

  static let patience: TimeInterval = 600

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let left = until.timeIntervalSince(fixedNow ?? context.date)
      ZStack {
        Circle().stroke(Palette.fillStrong, lineWidth: 2)
        Circle()
          .trim(from: 0, to: max(0, min(1, left / Self.patience)))
          .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      .frame(width: 20, height: 20)
    }
    .overlay {
      Button(action: cancel) {
        Image(systemName: Symbols.cancel)
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(Palette.inkMuted)
          .frame(width: 24, height: 24)
          .background(Circle().fill(Palette.surface))
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .opacity(hovering ? 1 : 0)
      .help(Text(.loci("connectors.cancel")))
      .accessibilityLabel(Text(.loci("connectors.cancel")))
    }
    .frame(width: 64, height: 28)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .animation(Motion.quick, value: hovering)
  }
}

/// In place of connecting, on another Mac: the name of the Mac the companion lives on, which cannot be pressed.
struct AwayPill: View {
  let mac: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "desktopcomputer").font(.system(size: 11))
      Text(verbatim: mac).lineLimit(1)
    }
    .font(Typography.button.weight(.medium))
    .foregroundStyle(Palette.inkFaint)
    .padding(.horizontal, 14)
    .frame(height: 28)
    .background(Capsule(style: .circular).strokeBorder(Palette.lineStrong, lineWidth: 1))
    .fixedSize()
    .accessibilityLabel(Text(.loci("connectors.away \(mac)")))
  }
}

/// Opens a page in the person's default browser, where they are signed in.
struct OpenInBrowser {
  let action: @MainActor (URL) -> Void

  @MainActor func callAsFunction(_ url: URL) { action(url) }
}

extension EnvironmentValues {
  @Entry var openInBrowser = OpenInBrowser { NSWorkspace.shared.open($0) }
}
