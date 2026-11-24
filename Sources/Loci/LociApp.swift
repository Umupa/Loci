import LociUI
import SwiftUI

@main
struct LociApp: App {
  @NSApplicationDelegateAdaptor private var delegate: LociAppDelegate
  @State private var launch = Launch()

  var body: some Scene {
    WindowGroup(id: MainWindow.id) {
      switch launch.state {
      case .running:
        RootView(
          folder: launch.folder, machines: launch.machines, updates: launch.updater, signIns: launch.signIns,
          reset: DataReset { [launch] in await launch.reset() }, talkShown: launch.talkShown
        )
        .id(launch.generation)
        .resetFailure($launch.resetFailure)
        .openingFiles(delegate.opened)
      case .problem(let problem):
        StartupProblemView(problem: problem, rebuild: launch.rebuild)
      }
    }
    .windowStyle(.hiddenTitleBar)
    .commands { LociCommands() }

    MenuBarExtra {
      MenuBarPanel(companion: launch.companion)
    } label: {
      MenuBarGlyph(companion: launch.companion)
    }
    .menuBarExtraStyle(.window)

    Window(Text(AppUpdateWindow.title), id: AppUpdateWindow.id) {
      AppUpdateWindow(updates: launch.updater)
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
    .windowResizability(.contentSize)
    .commandsRemoved()
  }
}
