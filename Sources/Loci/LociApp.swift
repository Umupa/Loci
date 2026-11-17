import LociUI
import SwiftUI

@main
struct LociApp: App {
  @State private var launch = Launch()

  var body: some Scene {
    WindowGroup {
      switch launch.state {
      case .running:
        RootView(folder: launch.folder, startShown: launch.startShown).lociHost(launch.host)
      case .problem(let problem):
        StartupProblemView(problem: problem, rebuild: launch.rebuild)
      }
    }
    .commands { LociCommands() }
    Settings {
      SettingsView(folder: launch.folder, version: Launch.version).lociHost(launch.host)
    }
  }
}
