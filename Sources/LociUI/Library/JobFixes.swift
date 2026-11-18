import Foundation
import LociModel
import SwiftUI

/// What each button on stopped work does: install what is missing, go where the reader can sign in or choose,
/// or try again.
@MainActor
struct JobFixes {
  let host: any LociModel.Host
  let openPlace: OpenPlace
  let browser: BrowserSession?
  let failed: ShowFailure
  /// Whether the Mac behind the window can take changes now; a fix that would change something waits until it can.
  let changesAllowed: Bool

  func apply(_ fix: JobLine.Fix, to item: Item) {
    guard changesAllowed || !fix.changesData else { return }
    switch fix {
    case .downloadComponent(let component), .update(let component):
      run(InstallComponent(component))
    case .downloadModel(let model):
      run(DownloadSpeechModel(model))
    case .signIn(let site):
      browser?.open(URL(string: "https://\(site)"))
      openPlace(.browser)
    case .chooseAgent:
      openPlace(.settings(.agents))
    case .chooseBrowserLogin:
      openPlace(.settings(.media))
    case .openSource:
      browser?.open(item.source)
      openPlace(.browser)
    case .retry, .resume:
      run(RetryJob(item: item.id))
    }
  }

  private func run<C: Command>(_ command: C) {
    Task {
      do throws(HostError) {
        _ = try await host.run(command)
      } catch {
        failed(error)
      }
    }
  }
}

extension JobLine.Fix {
  /// Whether the fix changes the data of the Mac behind the window, rather than going somewhere to look.
  var changesData: Bool {
    switch self {
    case .downloadComponent, .downloadModel, .update, .retry, .resume: true
    case .signIn, .chooseAgent, .chooseBrowserLogin, .openSource: false
    }
  }
}

/// Shows a failure in the window's alert.
struct ShowFailure {
  let action: (HostError) -> Void

  func callAsFunction(_ error: HostError) {
    action(error)
  }
}

extension EnvironmentValues {
  @Entry var showFailure = ShowFailure { _ in }
}
