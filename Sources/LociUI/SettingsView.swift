import AppKit
import SwiftUI

/// The settings window. Only what can already be set or seen is here.
public struct SettingsView: View {
  let folder: URL
  let version: String

  public init(folder: URL, version: String) {
    self.folder = folder
    self.version = version
  }

  public var body: some View {
    TabView {
      Tab {
        general
      } label: {
        Label {
          Text(.loci("settings.general"))
        } icon: {
          Image(systemName: Symbols.settings)
        }
      }
    }
    .frame(width: Size.settingsWidth)
    .tint(Palette.accent)
  }

  private var general: some View {
    Form {
      LabeledContent {
        HStack(spacing: Spacing.xs) {
          Text(verbatim: folder.path(percentEncoded: false))
            .font(Typography.mono)
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
          Button {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
          } label: {
            Text(.loci("settings.reveal"))
          }
        }
      } label: {
        Text(.loci("settings.folder"))
      }
      LabeledContent {
        Text(verbatim: version).textSelection(.enabled)
      } label: {
        Text(.loci("settings.version"))
      }
    }
    .formStyle(.grouped)
  }
}
