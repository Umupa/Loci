import AppKit
import LociModel
import SwiftUI

/// What opens from the menu bar icon: the companion's face and name with what it is busy with, then opening the
/// window and quitting.
public struct MenuBarPanel: View {
  let companion: MenuBarCompanion
  @Environment(\.openWindow) private var openWindow
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var highlighted: Choice?

  enum Choice: Hashable { case open, quit }

  public init(companion: MenuBarCompanion) {
    self.companion = companion
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      if let next = companion.next { NextLine(next: next) }
      Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline).padding(.vertical, 5)
        .padding(.horizontal, Spacing.xs)
      row(.open, symbol: Symbols.window, title: Text(.loci("menubar.open")))
      row(.quit, symbol: Symbols.quit, title: Text(.loci("menubar.quit")), shortcut: "⌘Q")
    }
    .padding(5)
    .frame(width: Self.width)
    .environment(\.lociFace, companion.face)
    .lociAppearance()
  }

  private var header: some View {
    HStack(spacing: 10) {
      LociAvatar(size: Self.face)
        .overlay {
          BreathingRing(color: Tones.accent, width: 1.5, breathing: companion.work != nil, period: 2.8)
            .padding(-3)
            .opacity(companion.work == nil ? 0 : 1)
        }
      VStack(alignment: .leading, spacing: 1) {
        name.font(.system(size: 14, weight: .semibold, design: .serif)).lineLimit(1)
        if let work = companion.work {
          Text(work.words)
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.inkMuted)
            .lineLimit(1)
            .truncationMode(.tail)
            .id(work.said)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
        }
      }
      .animation(reduceMotion ? nil : Motion.swap, value: companion.work?.said)
      Spacer(minLength: 0)
    }
    .foregroundStyle(Palette.ink)
    .padding(.horizontal, 8)
    .padding(.top, 6)
    .padding(.bottom, 4)
    .accessibilityElement(children: .combine)
  }

  private var name: Text {
    companion.name.isEmpty ? Text(.loci("companion.title")) : Text(verbatim: companion.name)
  }

  private func row(_ choice: Choice, symbol: String, title: Text, shortcut: String? = nil) -> some View {
    Button {
      choose(choice)
    } label: {
      HStack(spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: 13))
          .foregroundStyle(Palette.inkMuted)
          .frame(width: 18)
        title.lineLimit(1)
        Spacer(minLength: 0)
        if let shortcut { Text(verbatim: shortcut).foregroundStyle(Palette.inkFaint) }
      }
      .font(Typography.body)
      .foregroundStyle(Palette.ink)
      .padding(.horizontal, 8)
      .frame(height: 26)
      .background(
        RoundedRectangle(cornerRadius: Radius.thumbnail).fill(highlighted == choice ? Palette.fillStrong : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { inside in
      if inside { highlighted = choice } else if highlighted == choice { highlighted = nil }
    }
  }

  private func choose(_ choice: Choice) {
    switch choice {
    case .open: MainWindow.bringForward(open: openWindow)
    case .quit: NSApp.terminate(nil)
    }
  }

  private static let width: CGFloat = 260
  private static let face: CGFloat = 32
}

/// The timer that comes due next: a clock, what it is, and when.
private struct NextLine: View {
  @Environment(\.fixedNow) private var fixedNow
  let next: NextTimer

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: Symbols.schedule)
        .font(.system(size: 12))
        .foregroundStyle(Palette.inkMuted)
        .frame(width: 18)
      Text(verbatim: next.title).lineLimit(1).truncationMode(.tail)
      Spacer(minLength: Spacing.xs)
      TimerTime.label(next.due.date, now: fixedNow ?? Date())
        .font(.system(size: 11.5).monospaced())
        .foregroundStyle(Palette.inkMuted)
        .fixedSize()
    }
    .font(Typography.body)
    .foregroundStyle(Palette.ink)
    .padding(.horizontal, 8)
    .frame(height: 26)
    .accessibilityElement(children: .combine)
  }
}

/// The app's main window, which the menu bar brings back after it was closed.
@MainActor
public enum MainWindow {
  /// The scene id of the window group.
  public static let id = "main"

  /// Brings the open window to the front, or opens one when every window was closed.
  static func bringForward(open: OpenWindowAction) {
    NSApp.activate()
    let shown = NSApp.windows.first {
      $0.identifier?.rawValue.hasPrefix(id) == true && ($0.isVisible || $0.isMiniaturized)
    }
    guard let shown else { return open(id: id) }
    if shown.isMiniaturized { shown.deminiaturize(nil) }
    shown.makeKeyAndOrderFront(nil)
  }
}

/// Keeps Loci running with every window closed, so the companion goes on working and the menu bar stays,
/// hands the files the Finder opens with Loci to the window, and puts a downloaded update in place on quitting.
public final class LociAppDelegate: NSObject, NSApplicationDelegate {
  @MainActor public let opened = OpenedFiles()
  @MainActor public let cards = CardDelivery()
  @MainActor public var updates: any Updates = NoUpdates()

  /// Clicks on card notifications reach the app from its first moment, even one that launched it.
  @MainActor public func applicationWillFinishLaunching(_ notification: Notification) {
    cards.receiveClicks()
  }

  public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  @MainActor public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    finishUpdate { sender.reply(toApplicationShouldTerminate: true) }
    return .terminateLater
  }

  /// Puts a downloaded update in place, then calls `reply`. Quitting from code happens inside a main-actor job,
  /// and AppKit waits for the reply in a modal loop that runs no other main-actor work while that job lasts, so
  /// the update is put in place off the main actor and the reply arrives as a run loop block.
  @MainActor func finishUpdate(then reply: @escaping @MainActor () -> Void) {
    Self.finish(updates) {
      RunLoop.main.perform(inModes: [.default, .modalPanel, .eventTracking]) { MainActor.assumeIsolated(reply) }
    }
  }

  private nonisolated static func finish(_ updates: any Updates, then reply: @escaping @Sendable () -> Void) {
    Task {
      await updates.finishOnQuit()
      reply()
    }
  }

  @MainActor public func application(_ application: NSApplication, open urls: [URL]) {
    opened.open(urls)
  }
}
