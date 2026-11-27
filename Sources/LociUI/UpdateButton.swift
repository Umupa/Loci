import AppKit
import LociModel
import SwiftUI

/// A round button at the foot of the sidebar that appears once a newer Loci has downloaded by itself. Clicking
/// it restarts into the new copy, or waits while Loci is busy; clicking again while it waits restarts at once.
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
    case .failed:
      Task { await updates.retry() }
    case .ready, .waiting:
      Task { await updates.restart() }
    case .current, .downloading:
      break
    }
  }
}

/// How the update button looks in each state.
struct UpdateMark: View {
  let state: AppUpdate
  let act: () -> Void
  @State private var hovering = false

  var body: some View {
    if let symbol {
      Button(action: act) {
        ZStack {
          Circle().fill(amber ? Palette.accent : hovering ? Palette.fillStrong : Palette.fill)
          Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(amber ? Palette.onAccent : Palette.ink)
        }
        .frame(width: Size.updateButton, height: Size.updateButton)
        .contentShape(Circle())
      }
      .buttonStyle(PressStyle())
      .onHover { hovering = $0 }
      .help(Text(title))
      .accessibilityLabel(Text(title))
    }
  }

  /// `nil` while there is nothing to click: no newer release, or one still on its way in.
  private var symbol: String? {
    switch state {
    case .ready: Symbols.restart
    case .waiting: Symbols.waiting
    case .failed: Symbols.retry
    case .current, .downloading: nil
    }
  }

  private var amber: Bool {
    switch state {
    case .ready, .waiting: true
    case .current, .downloading, .failed: false
    }
  }

  private var title: LocalizedStringResource {
    switch state {
    case .waiting(_, let busy): UpdateWords.waiting(for: busy)
    case .failed(_, let failure): UpdateWords.failed(failure)
    case .current, .downloading, .ready: .loci("update.ready")
    }
  }
}

enum UpdateWords {
  static func failed(_ failure: UpdateFailure) -> LocalizedStringResource {
    switch failure {
    case .download: .loci("update.failedDownload")
    case .checksum: .loci("update.failedChecksum")
    case .signature: .loci("update.failedSignature")
    case .install: .loci("update.failedInstall")
    }
  }

  static func waiting(for busy: Busy) -> LocalizedStringResource {
    switch busy {
    case .answering: .loci("update.waitingAnswering")
    case .running: .loci("update.waitingRunning")
    case .library: .loci("update.waitingLibrary")
    }
  }
}

extension EnvironmentValues {
  /// Updating the copy of Loci that is running.
  @Entry var updates: any Updates = NoUpdates()
}
