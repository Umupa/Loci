import LociModel
import SwiftUI

/// The programs video and podcasts need, the speech models to recognize what is said, and how sites are signed
/// in to.
struct MediaSettingsPage: View {
  @Environment(\.host) private var host
  @State private var feed: Feed<MediaSetup>?

  var body: some View {
    SettingsPage(symbol: Symbols.media, title: .loci("settings.media"), width: Size.wideSettingsWidth) {
      Group {
        if let setup = feed?.value {
          StorageSection()
          VStack(alignment: .leading, spacing: 6) {
            SettingsGroup(title: .loci("media.components"), inset: 50) {
              ForEach(setup.components.filter { $0.component != .bundledPi }, id: \.component) { status in
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
struct ComponentRow: View {
  @Environment(\.colorScheme) private var scheme
  let status: ComponentStatus
  let work: Transfer?
  var install: (() -> Void)?

  var body: some View {
    SettingsRow {
      HStack(spacing: 10) {
        tile
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
          label
          if status.component != .bundledPi || work == nil {
            detail.font(Typography.mono).foregroundStyle(Palette.inkMuted)
          }
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
        Text(verbatim: reason).font(.system(size: 12)).foregroundStyle(Palette.inkMuted).lineLimit(1).help(reason)
        if let install { Button(action: install) { Text(.loci("job.retry")) }.buttonStyle(PushStyle()) }
      case nil:
        if let install { actions(install) }
      }
    }
  }

  @ViewBuilder private func actions(_ install: @escaping () -> Void) -> some View {
    if case .missing = status.installation {
      Button(action: install) { Text(.loci("media.download")) }.buttonStyle(PushStyle())
    } else if status.component == .ytDlp {
      Button(action: install) { Text(.loci("job.update")) }.buttonStyle(PushStyle())
    }
    if status.component != .bundledPi {
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

  private var label: Text {
    status.component == .bundledPi ? Text(.loci("agents.bundledPi")) : Text(verbatim: status.component.name)
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
    RoundedRectangle(cornerRadius: 7)
      .fill(Palette.fill)
      .overlay {
        if let mark = MarkArt.component(status.component, in: scheme) {
          Image(nsImage: mark)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
        } else {
          Image(systemName: fallback)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Palette.inkMuted)
        }
      }
      .frame(width: Size.componentTile, height: Size.componentTile)
      .accessibilityHidden(true)
  }

  private var fallback: String {
    switch status.component {
    case .ytDlp: Symbols.download
    case .ffmpeg: "film"
    case .quickJS: "curlybraces"
    case .bundledPi: Symbols.models
    }
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
