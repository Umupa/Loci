import LociModel
import SwiftUI

/// Starts this Mac's Loci over: the data folder goes to the Trash with only the settings kept, and the window
/// opens again on the empty folder. Only the window showing this Mac has one.
public struct DataReset: Sendable {
  let run: @MainActor @Sendable () async -> Void

  public init(_ run: @escaping @MainActor @Sendable () async -> Void) {
    self.run = run
  }
}

extension EnvironmentValues {
  @Entry var dataReset: DataReset?
}

extension View {
  /// Tells the person a reset that did not go through. The folder is as it was.
  public func resetFailure(_ failure: Binding<HostError?>) -> some View {
    alert(
      Text(.loci("reset.failed")),
      isPresented: Binding(get: { failure.wrappedValue != nil }, set: { if !$0 { failure.wrappedValue = nil } }),
      presenting: failure.wrappedValue
    ) { _ in
      Button(role: .cancel) {
      } label: {
        Text(.loci("dialog.ok"))
      }
    } message: { error in
      Text(Messages.describe(error))
    }
  }
}

/// The row that resets, and the question it asks first.
struct ResetRow: View {
  let reset: DataReset
  @State private var asking = false
  @State private var resetting = false

  var body: some View {
    SettingsRow {
      Text(.loci("reset.title"))
    } trailing: {
      if resetting {
        ProgressView().controlSize(.small)
      } else {
        Button {
          asking = true
        } label: {
          Text(.loci("reset.button"))
        }
        .buttonStyle(PushStyle())
      }
    }
    .confirmationDialog(Text(.loci("reset.question")), isPresented: $asking) {
      Button(role: .destructive) {
        resetting = true
        Task { await reset.run() }
      } label: {
        Text(.loci("reset.confirm"))
      }
      Button(role: .cancel) {
      } label: {
        Text(.loci("reset.cancel"))
      }
    } message: {
      Text(.loci("reset.message"))
    }
  }
}
