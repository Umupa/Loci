import LociModel
import SwiftUI

public struct AppUpdateWindow: View {
  public static let id = "app-update"
  public static var title: LocalizedStringResource { .loci("update.check") }

  private let updates: any Updates
  private let version: String
  @State private var status = Status.checking
  @State private var attempt = 0

  private enum Status {
    case checking
    case checked(AppUpdate)
    case failed(UpdateCheckError)
  }

  public init(updates: any Updates) {
    self.init(updates: updates, version: AppVersion(of: .main).number)
  }

  init(updates: any Updates, version: String) {
    self.updates = updates
    self.version = version
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      content
    }
    .padding(Spacing.l)
    .frame(width: 352, alignment: .leading)
    .frame(minHeight: 128, alignment: .leading)
    .foregroundStyle(Palette.ink)
    .background(Palette.canvas)
    .task(id: attempt) { await check() }
  }

  @ViewBuilder private var content: some View {
    switch status {
    case .checking:
      HStack {
        ProgressView().controlSize(.small)
        Text(.loci("update.checking"))
      }
    case .failed(.unsupported):
      Text(.loci("update.unsupported"))
    case .failed(.unavailable):
      Text(.loci("update.checkFailed"))
      action(.loci("job.retry")) { attempt += 1 }
    case .checked(.current):
      Text(.loci("update.current \(version)"))
      action(Self.title) { attempt += 1 }
    case .checked(.downloading(let release, let progress)):
      Text(.loci("update.downloading \(release.version.description)"))
      if let progress {
        ProgressView(value: progress.value)
      } else {
        ProgressView().progressViewStyle(.linear)
      }
    case .checked(.ready(let release)):
      Text(.loci("update.found \(release.version.description)"))
      action(.loci("update.ready")) { Task { await updates.restart() } }
    case .checked(.waiting(_, let busy)):
      Text(UpdateWords.waiting(for: busy))
      action(.loci("update.now")) { Task { await updates.restart() } }
    case .checked(.failed(_, let failure)):
      Text(UpdateWords.failed(failure))
      action(.loci("job.retry")) { Task { await updates.retry() } }
    }
  }

  private func action(_ title: LocalizedStringResource, perform: @escaping () -> Void) -> some View {
    Button(action: perform) { Text(title) }
      .buttonStyle(PushStyle())
      .keyboardShortcut(.defaultAction)
      .frame(maxWidth: .infinity, alignment: .trailing)
  }

  private func check() async {
    status = .checking
    do {
      try await updates.check()
    } catch {
      if !Task.isCancelled { status = .failed(error) }
      return
    }
    guard !Task.isCancelled else { return }
    for await next in updates.states() { status = .checked(next) }
  }
}
