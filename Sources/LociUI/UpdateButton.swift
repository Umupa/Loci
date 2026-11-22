import AppKit
import LociModel
import SwiftUI

/// A round button at the foot of the sidebar that appears only when a newer Loci is out. Clicking it downloads
/// the release, a ring fills while it does, and once it is ready clicking again quits and opens the new copy.
struct UpdateButton: View {
  @Environment(\.updates) private var updates
  @State private var state = AppUpdate.current

  var body: some View {
    HStack(spacing: 0) { UpdateMark(state: state, act: act) }
      .task {
        for await next in updates.states() { state = next }
      }
  }

  private func act() {
    switch state {
    case .available, .failed:
      Task { await updates.download() }
    case .ready:
      Task { await updates.installAndRestart() }
    case .current, .downloading:
      break
    }
  }
}

extension Updates {
  @MainActor func installAndRestart() async {
    if await install() { NSApplication.shared.terminate(nil) }
  }
}

/// How the update button looks in each state.
struct UpdateMark: View {
  let state: AppUpdate
  let act: () -> Void
  @State private var hovering = false

  var body: some View {
    if let release {
      Button(action: act) {
        ZStack {
          Circle().fill(ready ? Palette.accent : hovering ? Palette.fillStrong : Palette.fill)
          if case .downloading(_, let share) = state {
            Circle().stroke(Palette.line, lineWidth: 2)
            Circle()
              .trim(from: 0, to: max(share?.value ?? 0, 0.04))
              .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
              .rotationEffect(.degrees(-90))
          }
          Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ready ? Palette.onAccent : Palette.ink)
        }
        .frame(width: Size.updateButton, height: Size.updateButton)
        .contentShape(Circle())
      }
      .buttonStyle(PressStyle())
      .disabled(downloading)
      .onHover { hovering = $0 }
      .help(Text(title(release)))
      .accessibilityLabel(Text(title(release)))
    }
  }

  private var release: AppRelease? {
    switch state {
    case .current: nil
    case .available(let release), .downloading(let release, _), .ready(let release), .failed(let release, _): release
    }
  }

  private var ready: Bool {
    if case .ready = state { true } else { false }
  }

  private var downloading: Bool {
    if case .downloading = state { true } else { false }
  }

  private var symbol: String {
    switch state {
    case .ready: Symbols.restart
    case .failed: Symbols.retry
    case .downloading: Symbols.download
    case .current, .available: Symbols.update
    }
  }

  private func title(_ release: AppRelease) -> LocalizedStringResource {
    let version = release.version.description
    return switch state {
    case .ready: .loci("update.ready")
    case .failed(_, let reason): .loci("update.failed \(reason)")
    case .downloading: .loci("update.downloading \(version)")
    case .current, .available: .loci("update.available \(version)")
    }
  }
}

extension EnvironmentValues {
  /// Updating the copy of Loci that is running.
  @Entry var updates: any Updates = NoUpdates()
}
