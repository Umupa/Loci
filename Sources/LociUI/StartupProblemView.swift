import AppKit
import LociModel
import SwiftUI

/// Why Loci could not start, and what can be done about it.
public enum StartupProblem: Equatable, Sendable {
  case database(HostStartError)
  /// The data folder is one Loci must not touch, such as the older app's.
  case refusedFolder(String)
}

/// Shown instead of the window's content when storage could not start. Nothing has been changed yet; the
/// person chooses.
public struct StartupProblemView: View {
  let problem: StartupProblem
  let rebuild: () -> Void

  public init(problem: StartupProblem, rebuild: @escaping () -> Void) {
    self.problem = problem
    self.rebuild = rebuild
  }

  public var body: some View {
    VStack(spacing: Spacing.l) {
      Image(systemName: Symbols.problem)
        .font(.system(size: Size.emptySymbol))
        .foregroundStyle(Palette.accent)
      Text(title)
        .font(Typography.title)
        .foregroundStyle(Palette.ink)
        .multilineTextAlignment(.center)
      HStack(spacing: Spacing.s) {
        Button {
          NSApplication.shared.terminate(nil)
        } label: {
          Text(.loci("startup.quit"))
        }
        if canRebuild {
          Button(action: rebuild) { Text(.loci("startup.rebuild")) }
            .buttonStyle(.borderedProminent)
        }
      }
      .controlSize(.large)
    }
    .padding(Spacing.xxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    .tint(Palette.accent)
    .help(Text(verbatim: detail))
  }

  private var title: LocalizedStringResource {
    switch problem {
    case .database(.databaseUnreadable): .loci("startup.unreadable")
    case .database(.databaseFromNewerVersion): .loci("startup.newer")
    case .database(.storage): .loci("startup.storage")
    case .refusedFolder: .loci("startup.refused")
    }
  }

  private var canRebuild: Bool {
    switch problem {
    case .database(.databaseUnreadable), .database(.databaseFromNewerVersion): true
    case .database(.storage), .refusedFolder: false
    }
  }

  private var detail: String {
    switch problem {
    case .database(.databaseUnreadable(let reason)), .database(.storage(let reason)): reason
    case .database(.databaseFromNewerVersion(let unknown)): unknown.joined(separator: ", ")
    case .refusedFolder(let path): path
    }
  }
}
