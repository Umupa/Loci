import LociModel
import SwiftUI

/// What the dock can do with the work it shows.
struct DockActions {
  let card: CardActions
  /// Deletes the items of Loci's batch that have not started; `nil` while Loci saves nothing.
  let stopSaving: () -> Void
}

/// Floating at the foot of the gallery while there is work: a glass capsule with a ring for how far the task
/// in front has got, its title and stage ruler, and the other tasks' covers stacked. Clicked, it opens upward
/// into the list of every task. While Loci saves, it counts Loci's batch and offers to stop it.
struct TaskDock: View {
  @Environment(\.standIns) private var standIns
  let jobs: [Job]
  let items: [EntityID: Item]
  let saving: SavingBatch?
  let actions: DockActions
  @State private var open = false

  /// The task in front, the one furthest along of those running, then the rest in order; `nil` when there is
  /// no work.
  static func arrange(_ jobs: [Job]) -> (lead: Job, rest: [Job])? {
    let running = jobs.filter { if case .running = $0.state { true } else { false } }
    guard
      let lead = running.first(where: { if case .running(_?, _) = $0.state { true } else { false } }) ?? running.first
        ?? jobs.first
    else { return nil }
    return (lead, jobs.filter { $0.item != lead.item })
  }

  /// How much of the foot of the gallery the dock covers, with its margin, so the last row can scroll clear.
  static let room: CGFloat = 56 + 20 + 12

  /// `3 / 5`: the item Loci is on now, of all it is saving.
  static func count(of batch: SavingBatch) -> String {
    "\(min(batch.finished + 1, batch.items.count)) / \(batch.items.count)"
  }

  /// How much of all the job's work is done, from its ruler.
  static func overall(_ job: Job, kind: Item.Kind) -> Double {
    let segments = StageRuler.segments(of: job, kind: kind)
    let total = segments.map(\.weight).reduce(0, +)
    guard total > 0 else { return 0 }
    let done = segments.map { segment -> Double in
      switch segment.mark {
      case .done: segment.weight
      case .running(let progress?): segment.weight * progress.value
      default: 0
      }
    }
    return done.reduce(0, +) / total
  }

  private var shown: [Job] { jobs.filter { items[$0.item] != nil } }
  private var isOpen: Bool { open || standIns?.taskDockOpen == true }

  var body: some View {
    if let (lead, rest) = Self.arrange(shown), let item = items[lead.item] {
      VStack(spacing: 8) {
        if isOpen {
          TaskList(jobs: shown, items: items, actions: actions.card)
            .transition(.scale(scale: 0.96, anchor: .bottom).combined(with: .opacity).combined(with: .offset(y: 16)))
        }
        capsule(lead: lead, item: item, rest: rest)
      }
      .frame(width: Size.taskDock)
      .animation(Motion.dock, value: isOpen)
    }
  }

  private func capsule(lead: Job, item: Item, rest: [Job]) -> some View {
    Button {
      open.toggle()
    } label: {
      HStack(spacing: 12) {
        if let saving {
          lociSaving(saving)
        } else {
          ring(lead, item: item)
          VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
              .lineLimit(1)
            StageRuler(segments: StageRuler.segments(of: lead, kind: item.kind))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          stack(rest)
        }
        Image(systemName: "chevron.up")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Palette.inkMuted)
          .rotationEffect(.degrees(isOpen ? 180 : 0))
          .frame(width: Size.iconButton, height: Size.iconButton)
      }
      .padding(.leading, 10)
      .padding(.trailing, 8)
      .frame(height: 56)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .glassPanel(in: Capsule())
    .accessibilityLabel(Text(.loci("dock.expand")))
  }

  private func lociSaving(_ batch: SavingBatch) -> some View {
    HStack(spacing: 12) {
      LociAvatar(size: 32).overlay(Circle().strokeBorder(Palette.accent, lineWidth: 1.5).padding(-3))
      VStack(alignment: .leading, spacing: 2) {
        Text(.loci("dock.lociSaving")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
        Text(verbatim: Self.count(of: batch)).font(.system(size: 11.5).monospaced()).foregroundStyle(Palette.inkMuted)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Button(action: actions.stopSaving) { Text(.loci("dock.stop")) }
        .buttonStyle(PushStyle())
        .changesData()
    }
  }

  private func ring(_ job: Job, item: Item) -> some View {
    ZStack {
      Circle().stroke(Palette.fillStrong, lineWidth: 3)
      Circle().trim(from: 0, to: Self.overall(job, kind: item.kind))
        .stroke(Palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(-90))
      GalleryArt(item: item).frame(width: 24, height: 24).clipShape(Circle())
    }
    .frame(width: 36, height: 36)
    .animation(Motion.standard, value: Self.overall(job, kind: item.kind))
  }

  @ViewBuilder private func stack(_ rest: [Job]) -> some View {
    let shown = rest.prefix(2).compactMap { items[$0.item] }
    if !shown.isEmpty {
      HStack(spacing: -8) {
        ForEach(shown, id: \.id) { item in
          GalleryArt(item: item).blur(radius: 2).drawingGroup()
            .frame(width: 30, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.surface, lineWidth: 2))
        }
        if rest.count > shown.count {
          Text(verbatim: "+\(rest.count - shown.count)").font(.system(size: 11.5).monospaced())
            .foregroundStyle(Palette.inkMuted).padding(.leading, 14)
        }
      }
    }
  }
}

/// Every task as a row: a small cover, the title over its stage ruler, and on the right what can be done.
struct TaskList: View {
  let jobs: [Job]
  let items: [EntityID: Item]
  let actions: CardActions

  var body: some View {
    ScrollView {
      VStack(spacing: 2) {
        ForEach(jobs, id: \.item) { job in
          if let item = items[job.item] { TaskRow(job: job, item: item, actions: actions) }
        }
      }
      .padding(6)
    }
    .scrollIndicators(.never)
    .frame(maxHeight: 340)
    .fixedSize(horizontal: false, vertical: true)
    .glassPanel(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

private struct TaskRow: View {
  @Environment(\.standIns) private var standIns
  let job: Job
  let item: Item
  let actions: CardActions
  @State private var pointing = false

  private var state: CardState { CardState(job) }
  private var lit: Bool { pointing || standIns?.pointedCard == item.id }

  var body: some View {
    HStack(spacing: 12) {
      GalleryArt(item: item).blur(radius: 3).brightness(-0.08).drawingGroup()
        .frame(width: 64, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      VStack(alignment: .leading, spacing: 7) {
        Text(verbatim: item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
        StageRuler(segments: StageRuler.segments(of: job, kind: item.kind))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      trailing
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(lit ? Palette.fill : .clear))
    .contentShape(Rectangle())
    .onHover { pointing = $0 }
  }

  @ViewBuilder private var trailing: some View {
    if case .needs(let fix) = state {
      Button {
        actions.fix(fix, item)
      } label: {
        fix.label
      }.buttonStyle(PushStyle()).fixedSize()
        .changesData(fix.changesData)
    } else {
      HStack(spacing: 2) {
        if case .paused = state {
          IconButton(symbol: "play.fill", title: .loci("job.resume"), size: 26, symbolSize: 12) { actions.resume(item) }
        } else {
          IconButton(symbol: "pause.fill", title: .loci("job.pause"), size: 26, symbolSize: 12) { actions.pause(item) }
        }
        IconButton(symbol: "xmark", title: .loci("job.cancel"), size: 26, symbolSize: 12) { actions.cancel(item) }
      }
      .opacity(lit ? 1 : 0)
    }
  }
}
