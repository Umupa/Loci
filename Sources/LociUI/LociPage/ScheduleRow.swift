import LociModel
import SwiftUI

/// One schedule: its title, how often, where what it finds goes and its switch, over the last run's summary.
/// Clicking opens its latest runs; the context menu changes how often or removes it (WK-S2).
struct ScheduleRow: View {
  @Environment(\.host) private var host
  @Environment(\.showFailure) private var showFailure
  @Environment(\.fixedNow) private var fixedNow
  @Environment(\.reducesMotion) private var reduceMotion
  let entry: ScheduleEntry
  /// Panel titles by name, for where it goes.
  let panels: [String: String]
  @State private var open: Bool
  @State private var paused: Bool
  @State private var hovering = false
  @State private var runs: Feed<[Run]>?

  init(entry: ScheduleEntry, panels: [String: String], open: Bool = false) {
    self.entry = entry
    self.panels = panels
    _open = State(initialValue: open)
    _paused = State(initialValue: entry.paused)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          fold
          title.lineLimit(1).fixedSize(horizontal: true, vertical: false)
          Spacer(minLength: 0)
          tags
          toggle
        }
        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .top, spacing: 10) {
            fold.padding(.top, 4)
            title.lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            toggle
          }
          tags.padding(.leading, 20)
        }
      }
      if !open, let summary = entry.lastSummary {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          if let ran = entry.lastRun {
            TimerTime.label(ran.date, now: fixedNow ?? Date())
              .font(.system(size: 11.5).monospaced())
              .foregroundStyle(Palette.inkFaint)
              .fixedSize()
          }
          Text(verbatim: summary)
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.inkMuted)
            .lineLimit(1)
        }
        .padding(.leading, 20)
        .opacity(paused ? 0.45 : 1)
      }
      if open, let runs = runs?.value {
        RunList(runs: runs).padding(.leading, 24).padding(.top, 6).transition(.opacity)
      }
    }
    .foregroundStyle(Palette.ink)
    .padding(.vertical, 11)
    .padding(.leading, 14)
    .padding(.trailing, 14)
    .background(hovering ? Palette.fill : .clear)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .onTapGesture { withAnimation(reduceMotion ? nil : Motion.standard) { open.toggle() } }
    .contextMenu { menu }
    .onChange(of: entry.paused) { _, now in paused = now }
    .background {
      if open { Color.clear.subscribing(WatchScheduleRuns(entry.ref, limit: 5), into: $runs) }
    }
    .accessibilityAddTraits(.isButton)
  }

  private var fold: some View {
    Image(systemName: Symbols.fold)
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(Palette.inkFaint)
      .rotationEffect(.degrees(open ? 90 : 0))
      .frame(width: 10)
  }

  private var title: some View {
    Text(verbatim: entry.title)
      .font(.system(size: 13.5, weight: .medium))
      .opacity(paused ? 0.45 : 1)
  }

  /// How often and where to: each keeps its own width and never wraps.
  private var tags: some View {
    HStack(spacing: 10) {
      if entry.calendarUncovered == true {
        Circle().strokeBorder(Palette.accent, lineWidth: 1.4).frame(width: 6, height: 6)
          .help(Text(.loci("timers.calendarUncovered")))
          .accessibilityLabel(Text(.loci("timers.calendarUncovered")))
      }
      entry.every.words
        .font(.system(size: 11.5).monospaced())
        .foregroundStyle(Palette.inkMuted)
        .lineLimit(1)
        .fixedSize()
        .opacity(paused ? 0.45 : 1)
      DestinationChip(destination: entry.destination, panels: panels).fixedSize().opacity(paused ? 0.5 : 1)
    }
  }

  private var toggle: some View {
    Toggle(isOn: Binding(get: { !paused }, set: pause)) { Text(verbatim: entry.title) }
      .labelsHidden()
      .toggleStyle(AmberSwitch(small: true))
      .changesData()
  }

  @ViewBuilder private var menu: some View {
    Menu {
      ForEach(entry.every.choices, id: \.self) { every in
        Toggle(isOn: Binding(get: { every == entry.every }, set: { if $0 { change(every) } })) { every.words }
      }
    } label: {
      Text(.loci("timers.every"))
    }
    .changesData()
    Divider()
    Button(role: .destructive) {
      remove()
    } label: {
      Text(.loci("timers.remove"))
    }
    .changesData()
  }

  private func pause(_ running: Bool) {
    paused = !running
    send(PauseSchedule(entry.ref, paused: !running)) { paused = entry.paused }
  }

  private func change(_ every: Every) {
    send(ChangeSchedule(entry.ref, every: every)) {}
  }

  private func remove() {
    send(RemoveSchedule(entry.ref)) {}
  }

  private func send<C: Command>(_ command: C, undo: @escaping @MainActor () -> Void) {
    Task {
      do throws(HostError) {
        _ = try await host.run(command)
      } catch {
        undo()
        showFailure(error)
      }
    }
  }
}

/// Where a schedule's runs put what they find: a panel, in amber, or only the day's notes.
private struct DestinationChip: View {
  let destination: Destination
  let panels: [String: String]

  var body: some View {
    HStack(spacing: 4) {
      switch destination {
      case .panel(let name):
        Image(systemName: Symbols.panel).font(.system(size: 9.5))
        Text(verbatim: panels[name] ?? name)
      case .notes:
        Image(systemName: Symbols.notes).font(.system(size: 9.5))
        Text(.loci("timers.notes"))
      }
    }
    .font(.system(size: 11.5))
    .lineLimit(1)
    .foregroundStyle(isPanel ? Palette.accentInk : Palette.inkMuted)
    .padding(.vertical, 1)
    .padding(.leading, 6)
    .padding(.trailing, 8)
    .background(isPanel ? Palette.tint : Palette.fill, in: Capsule())
  }

  private var isPanel: Bool {
    if case .panel = destination { return true }
    return false
  }
}

/// A schedule's latest runs on a thin line: when, what it found and what it read; a run that failed says why.
private struct RunList: View {
  @Environment(\.fixedNow) private var fixedNow
  let runs: [Run]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(runs) { run in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Circle()
            .strokeBorder(dot(run.outcome), lineWidth: 1.5)
            .frame(width: 8, height: 8)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
          VStack(alignment: .leading, spacing: 3) {
            TimerTime.label(run.startedAt.date, now: fixedNow ?? Date())
              .font(.system(size: 11.5).monospaced())
              .foregroundStyle(Palette.inkFaint)
            found(run.outcome)
          }
        }
      }
    }
    .background(alignment: .leading) {
      Rectangle().fill(Palette.lineStrong).frame(width: 1.5).padding(.vertical, 6).padding(.leading, 3.25)
    }
  }

  private func dot(_ outcome: Run.Outcome) -> Color {
    if case .failed = outcome { return Palette.failure }
    return Palette.accent
  }

  @ViewBuilder private func found(_ outcome: Run.Outcome) -> some View {
    switch outcome {
    case .running:
      Text(.loci("timers.running")).font(.system(size: 13)).foregroundStyle(Palette.inkMuted)
    case .finished(let summary, let sources):
      Text(verbatim: summary).font(.system(size: 13)).lineSpacing(3).foregroundStyle(Palette.ink)
      if !sources.isEmpty { RunSources(sources: sources) }
    case .failed(let reason, _):
      Text(verbatim: reason).font(.system(size: 13)).foregroundStyle(Palette.inkMuted)
    }
  }
}

/// What a run read, each on a small gray tag: a site by its address, anything else as it was named.
struct RunSources: View {
  let sources: [String]

  var body: some View {
    FlowRow(spacing: 6) {
      ForEach(sources, id: \.self) { source in
        Text(verbatim: Self.name(source))
          .font(.system(size: 11.5))
          .foregroundStyle(Palette.inkMuted)
          .lineLimit(1)
          .truncationMode(.middle)
          .padding(.vertical, 1)
          .padding(.horizontal, 7)
          .background(Palette.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
      }
    }
  }

  /// `github.com/TencentCloud/CubeSandbox/releases` reads as `TencentCloud/CubeSandbox`, other pages as their site.
  static func name(_ source: String) -> String {
    guard let url = URL(string: source), let host = url.host() else { return source }
    let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    let parts = url.pathComponents.filter { $0 != "/" }
    if site == "github.com", parts.count >= 2 { return "\(parts[0])/\(parts[1])" }
    return site
  }
}
