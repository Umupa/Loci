import LociUI
import SwiftUI

@main
struct LociApp: App {
  @State private var launch = Launch()

  var body: some Scene {
    WindowGroup {
      switch launch.state {
      case .running:
        RootView(
          folder: launch.folder, machines: launch.machines, updates: launch.updater, signIns: launch.signIns,
          talkShown: launch.talkShown)
      case .problem(let problem):
        StartupProblemView(problem: problem, rebuild: launch.rebuild)
      }
    }
    .windowStyle(.hiddenTitleBar)
    .commands { LociCommands() }

    Window(Text(AppUpdateWindow.title), id: AppUpdateWindow.id) {
      AppUpdateWindow(updates: launch.updater)
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
    .windowResizability(.contentSize)
    .commandsRemoved()
  }
}
