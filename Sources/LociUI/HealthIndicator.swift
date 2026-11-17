import LociModel
import SwiftUI

/// A toolbar mark that appears only when something needs attention: files that could not be used, or a
/// database that stopped working. A rebuild that takes a moment shows as a small spinner.
struct HealthIndicator: View {
  let health: Health?
  @State private var showing = false
  @State private var slowRebuild = false

  var body: some View {
    HStack(spacing: Spacing.xs) {
      if slowRebuild {
        ProgressView().controlSize(.small)
      }
      if needsAttention, let health {
        Button {
          showing.toggle()
        } label: {
          Image(systemName: Symbols.problem).foregroundStyle(Palette.accent)
        }
        .help(Text(.loci("health.problems")))
        .popover(isPresented: $showing) { ProblemList(health: health) }
      }
    }
    .task(id: rebuilding) {
      slowRebuild = false
      guard rebuilding else { return }
      try? await Task.sleep(for: Motion.quietDelay)
      slowRebuild = !Task.isCancelled
    }
  }

  private var rebuilding: Bool { health?.database == .rebuilding }

  private var needsAttention: Bool {
    guard let health else { return false }
    if case .failed = health.database { return true }
    return !health.fileProblems.isEmpty
  }
}

struct ProblemList: View {
  let health: Health

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.m) {
        if case .failed(let reason) = health.database {
          Text(.loci("health.databaseFailed"))
            .font(Typography.bodyEmphasis)
            .foregroundStyle(Palette.ink)
            .help(Text(verbatim: reason))
        }
        ForEach(health.fileProblems, id: \.self) { problem in
          VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(Messages.describe(problem.kind))
              .font(Typography.body)
              .foregroundStyle(Palette.ink)
            Text(verbatim: problem.path)
              .font(Typography.mono)
              .foregroundStyle(Palette.inkMuted)
              .textSelection(.enabled)
          }
          .help(Text(verbatim: problem.reason))
        }
      }
      .padding(Spacing.m)
      .frame(width: Size.problemListWidth, alignment: .leading)
    }
  }
}
