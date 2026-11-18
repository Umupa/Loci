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

  func apply(_ fix: JobLine.Fix, to item: EntityID) {
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
    case .retry, .resume:
      run(RetryJob(item: item))
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
