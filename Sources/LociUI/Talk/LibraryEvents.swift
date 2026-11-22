import LociModel
import SwiftUI

/// An item going into the library while its work runs or after it stopped: its card, with the step going on
/// and how far along, or why it stopped.
struct SavingCard: View {
  @Environment(\.openPage) private var openPage
  let item: Item
  let job: Job

  var body: some View {
    let progress = JobSteps.progress(of: job, kind: item.kind)
    Button {
      openPage(.item(item.id))
    } label: {
      LibraryCard(item: item, line: line(progress), progress: problem == nil ? progress : nil)
        .frame(width: CardShell<EmptyView>.width)
    }
    .buttonStyle(PressStyle())
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func line(_ progress: Double) -> Text {
    if let problem { return problem.foregroundStyle(Palette.accentInk) }
    let stage = JobSteps.Step(job.stage, separateArticleStages: item.kind == .article && !job.stages.isEmpty)
    return Text(
      joining: Text(stage.name), Text(verbatim: " · "),
      Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit())
  }

  /// What stopped the work, in a few words.
  private var problem: Text? {
    switch JobLine(job) {
    case .action(let fix, let problem): fix.why(problem) ?? Text(.loci("conversation.stopped"))
    case .working, .none: nil
    }
  }
}

/// An item the person read to the end, as its card: when they finished it under its title.
struct FinishedCard: View {
  let item: Item
  let at: Date

  var body: some View {
    LibraryCards(items: [item]) { _ in
      Text(
        joining: Text(.loci("talk.finished")), Text(verbatim: " · "),
        Text(at, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
    }
  }
}
