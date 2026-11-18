import LociModel
import SwiftUI

/// The programs video and podcasts need, the speech models to recognize what is said, and how sites are signed
/// in to.
struct MediaSettingsPage: View {
  @Environment(\.host) private var host
  @State private var feed: Feed<MediaSetup>?

  var body: some View {
    SettingsPage(
      symbol: Symbols.media, title: .loci("settings.media"),
      tile: (Color(nsColor: NSColor(rgb: 0xF0B455)), Color(nsColor: NSColor(rgb: 0xD08414))),
      width: Size.wideSettingsWidth
    ) {
      Group {
        if let setup = feed?.value {
          VStack(alignment: .leading, spacing: 6) {
            SettingsGroup(title: .loci("media.components"), inset: 50) {
              ForEach(setup.components, id: \.component) { status in
                ComponentRow(
                  status: status, work: setup.componentWork.first { $0.component == status.component }?.state,
                  install: { run(InstallComponent(status.component)) })
              }
            }
            HStack {
              Spacer()
              Button {
                run(DetectComponents(again: true))
              } label: {
                Text(.loci("media.detectAgain")).font(Typography.button).foregroundStyle(Palette.accentInk)
              }
              .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
          }
          SpeechModels(setup: setup)
          SettingsGroup(title: .loci("media.network")) {
            SettingsRow {
              Text(.loci("media.browserLogin"))
            } trailing: {
              PopupPicker(
                selection: Binding(get: { setup.browserLogin }, set: { run(SetBrowserLogin($0)) }),
                options: BrowserLogin.allCases.map { ($0, $0.name) })
            }
            SettingsRow {
              Text(.loci("media.proxy"))
            } trailing: {
              Text(.loci("media.proxySystem")).font(.system(size: 12.5)).foregroundStyle(Palette.inkMuted)
            }
          }
        }
      }
      .changesData()
    }
    .subscribing(MediaSettings(), into: $feed)
  }

  private func run<C: Command>(_ command: C) {
    Task { _ = try? await host.run(command) }
  }
}

/// One program: its tile, name, version and where it came from, and what can be done about it.
private struct ComponentRow: View {
  let status: ComponentStatus
  let work: Transfer?
  let install: () -> Void

  var body: some View {
    SettingsRow {
      HStack(spacing: 10) {
        tile
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
          Text(verbatim: status.component.name)
          detail.font(Typography.mono).foregroundStyle(Palette.inkFaint)
        }
        .lineLimit(1)
      }
    } trailing: {
      switch work {
      case .running(let share):
        Meter(share: share?.value ?? 0, width: 52)
        Text(verbatim: share.map { "\(Int(($0.value * 100).rounded()))%" } ?? "").font(Typography.mono)
          .foregroundStyle(Palette.inkMuted)
      case .failed(let reason):
        Text(verbatim: reason).font(.system(size: 12)).foregroundStyle(Palette.inkMuted).lineLimit(1)
        Button(action: install) { Text(.loci("job.retry")) }.buttonStyle(PushStyle())
      case nil:
        if case .missing = status.installation {
          Button(action: install) { Text(.loci("media.download")) }.buttonStyle(PushStyle())
        } else if status.component == .ytDlp {
          Button(action: install) { Text(.loci("job.update")) }.buttonStyle(PushStyle())
        }
        Menu {
          Button(action: install) { Text(.loci("media.installManaged")) }
        } label: {
          Image(systemName: Symbols.more).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkMuted)
            .frame(width: 22, height: 22)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
      }
    }
  }

  /// `2026.10.26 · Homebrew`, `9.0.2 · 由 Loci 管理`, or that it is missing.
  private var detail: Text {
    switch status.installation {
    case .system(let path, let version):
      let source = path.contains("homebrew") || path.hasPrefix("/usr/local") ? "Homebrew" : path
      return Text(verbatim: [version, source].compactMap { $0 }.joined(separator: " · "))
    case .managed(let version):
      return Text(joining: Text(verbatim: version.map { $0 + " · " } ?? ""), Text(.loci("media.managed")))
    case .missing:
      return Text(.loci("media.missing"))
    }
  }

  private var tile: some View {
    let look: (String, UInt32, UInt32) =
      switch status.component {
      case .ytDlp: (Symbols.download, 0xE25B4A, 0xB73526)
      case .ffmpeg: ("film", 0x4FA05A, 0x2C7038)
      case .quickJS: ("curlybraces", 0xE9B23C, 0xC48A12)
      }
    return Image(systemName: look.0)
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: Size.componentTile, height: Size.componentTile)
      .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color(nsColor: NSColor(rgb: look.1)), Color(nsColor: NSColor(rgb: look.2))], startPoint: .top,
              endPoint: .bottom))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(
          .black.opacity(0.14), lineWidth: Size.hairline))
  }
}

extension BrowserLogin {
  var name: Text {
    switch self {
    case .none: Text(.loci("media.loginNone"))
    case .safari: Text(verbatim: "Safari")
    case .chrome: Text(verbatim: "Chrome")
    case .firefox: Text(verbatim: "Firefox")
    case .edge: Text(verbatim: "Edge")
    case .brave: Text(verbatim: "Brave")
    case .chromium: Text(verbatim: "Chromium")
    case .opera: Text(verbatim: "Opera")
    case .vivaldi: Text(verbatim: "Vivaldi")
    }
  }
}
