import LociModel
import SwiftUI

/// An item going into the library while its work runs or after it stopped: each step of the work, how far
/// along, and why it stopped.
struct SavingCard: View {
  let item: Item
  let job: Job
  let indent: CGFloat

  var body: some View {
    TaskCard(
      title: Text(joining: Text(.loci("talk.saving")), Text(verbatim: " · " + item.title)),
      progress: JobSteps.progress(of: job, kind: item.kind),
      steps: JobSteps.states(of: job, kind: item.kind).map { step in
        (Text(step.step.name), step.state)
      },
      problem: problem, indent: indent)
  }

  /// What stopped the work, in a few words.
  private var problem: Text? {
    switch JobLine(job) {
    case .action(let fix, let problem): fix.why(problem)
    case .working, .none: nil
    }
  }
}

/// An item that went into the library, ready to open, as a card in the conversation.
struct SavedItemCard: View {
  @Environment(\.openPage) private var openPage
  let item: Item

  var body: some View {
    Button {
      openPage(.item(item.id))
    } label: {
      ItemCard(title: item.title, source: item.site, duration: duration) {
        Cover(item: item, corner: 0)
      }
    }
    .buttonStyle(.plain)
  }

  private var duration: Text? {
    switch item.kind {
    case .video(let length?), .audio(let length?): Text(verbatim: MediaTime.text(length))
    default: nil
    }
  }
}
