import ServiceManagement
import SwiftUI

/// Whether Loci opens when the person logs in to this Mac.
@MainActor
protocol LoginItem {
  var state: LoginItemState { get }
  func turn(on: Bool) throws
  /// System Settings at Login Items, where the person allows what macOS held back.
  func showSystemSettings()
}

enum LoginItemState: Equatable {
  case off
  case on
  /// Turned on, and waiting for the person to allow it in System Settings.
  case awaitingApproval
}

/// The app itself as a login item, through the system's login item service.
struct SystemLoginItem: LoginItem {
  var state: LoginItemState {
    switch SMAppService.mainApp.status {
    case .enabled: .on
    case .requiresApproval: .awaitingApproval
    case .notRegistered, .notFound: .off
    @unknown default: .off
    }
  }

  func turn(on: Bool) throws {
    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
  }

  func showSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}

extension EnvironmentValues {
  @Entry var loginItem: any LoginItem = SystemLoginItem()
}

/// The General settings row that turns opening at login on and off.
struct LoginItemRow: View {
  @Environment(\.loginItem) private var item
  @State private var state = LoginItemState.off

  var body: some View {
    SettingsRow {
      Text(.loci("settings.openAtLogin"))
    } trailing: {
      if state == .awaitingApproval {
        Button(action: item.showSystemSettings) {
          Text(.loci("settings.allowInSystemSettings"))
        }
        .buttonStyle(PushStyle())
      }
      Toggle(isOn: Binding(get: { state != .off }, set: turn)) {
        Text(.loci("settings.openAtLogin"))
      }
      .labelsHidden()
      .toggleStyle(AmberSwitch(small: true))
    }
    .onAppear { state = item.state }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      state = item.state
    }
  }

  private func turn(_ on: Bool) {
    try? item.turn(on: on)
    state = item.state
  }
}
