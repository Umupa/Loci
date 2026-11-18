import LociModel
import SwiftUI

/// The work on an item as its own page tells it: what is going on, or what went wrong in full with the
/// button that helps. The program's own words stay folded away until asked for.
struct JobDetail: View {
  let line: JobLine
  let act: (JobLine.Fix) -> Void
  @State private var rawShown = false

  var body: some View {
    VStack(spacing: Spacing.s) {
      switch line {
      case .working(let activity, let progress):
        ActivityMark(activity: activity, progress: progress)
        Text(activity.name).font(.system(size: 12)).foregroundStyle(Palette.inkMuted)
      case .action(let fix, let problem):
        if let why = fix.why(problem) {
          why.font(Typography.bodyEmphasis).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
        }
        if let explanation = problem?.explanation {
          Text(explanation).font(.system(size: 12)).foregroundStyle(Palette.inkMuted)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        Button(action: { act(fix) }) { fix.label }.buttonStyle(PushStyle()).fixedSize()
        if let problem { raw(problem.reason) }
      case .none:
        EmptyView()
      }
    }
    .frame(maxWidth: Size.jobDetail)
  }

  @ViewBuilder private func raw(_ reason: String) -> some View {
    Button {
      withAnimation(Motion.fold) { rawShown.toggle() }
    } label: {
      HStack(spacing: 4) {
        Text(.loci("job.errorDetails"))
        Image(systemName: Symbols.fold).font(.system(size: 9, weight: .semibold))
          .rotationEffect(.degrees(rawShown ? 90 : 0))
      }
      .font(Typography.caption)
      .foregroundStyle(Palette.inkFaint)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    if rawShown {
      Text(verbatim: reason).font(Typography.mono).foregroundStyle(Palette.inkMuted)
        .textSelection(.enabled).multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
