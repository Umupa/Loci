import AppKit
import LociModel
import SwiftUI

/// A connector's mark on a small tile, by its id: GitHub in ink, the others in their colors, and a link for
/// any connector the app draws no mark for, such as an address the person added.
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
      .overlay { ConnectorArt(art: Self.art(for: id), size: size * 0.58) }
      .frame(width: size, height: size)
      .saturation(faded ? 0 : 1)
      .opacity(faded ? 0.55 : 1)
      .accessibilityHidden(true)
  }

  /// How a connector is drawn on its tile: a site's own mark in ink, a service's mark in its colors, a symbol
  /// for this Mac's calendars and reminders, a letter in ink for a site the app has no mark for, and a link
  /// for an address the person added.
  enum Art {
    case ink(String)
    case colored(NSImage)
    case symbol(String)
    case letter(String)
    case link
  }

  static func art(for id: ConnectorID) -> Art {
    switch id.rawValue {
    case "github", "x": .ink(id.rawValue)
    case "calendar": .symbol("calendar")
    case "reminders": .symbol("checklist")
    case "v2ex": .letter("V")
    case "xiaohongshu": .letter("小")
    case "bilibili": .letter("B")
    default: MarkArt.connector(id).map(Art.colored) ?? .link
    }
  }
}

/// A connector's mark itself, `size` across, without the tile or circle it sits on: the Connectors page and a
/// panel's sites draw a connector the same way.
struct ConnectorArt: View {
  let art: ConnectorMark.Art
  let size: CGFloat

  var body: some View {
    Group {
      switch art {
      case .ink(let name):
        if let art = MarkArt.site(name) {
          Image(nsImage: art).renderingMode(.template).resizable().scaledToFit().foregroundStyle(Palette.ink)
        }
      case .colored(let art):
        Image(nsImage: art).resizable().scaledToFit()
      case .symbol(let name):
        Image(systemName: name).resizable().scaledToFit().fontWeight(.medium).foregroundStyle(Palette.ink).padding(1)
      case .letter(let letter):
        Text(serif: letter, Serif.Face(size: size * 0.8, weight: .semibold)).foregroundStyle(Palette.ink)
          .minimumScaleFactor(0.5)
      case .link:
        Image(systemName: Symbols.link).resizable().scaledToFit().fontWeight(.medium)
          .foregroundStyle(Palette.inkMuted).padding(1)
      }
    }
    .frame(width: size, height: size)
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
