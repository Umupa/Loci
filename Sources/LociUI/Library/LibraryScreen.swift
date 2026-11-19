import AppKit
import LociModel
import SwiftUI

/// The library: the link field, what is being watched on a shelf of large covers, and every item in a list
/// below with the work on it. Pasting or dropping a link adds it too.
struct LibraryScreen: View {
  @Environment(\.host) private var host
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.openPlace) private var openPlace
  @Environment(\.browser) private var browser
  let kind: ItemKind?
  let chooseFiles: () -> Void
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  let delete: (Item) -> Void
  @State private var feed: Feed<[Item]>?
  @State private var jobs: Feed<[Job]>?
  /// Read once before the list shows, so the shelf does not push the list down after it appears.
  @State private var progress: Progress?

  var body: some View {
    let items = shown
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        LinkField(kind: kind, add: add, chooseFiles: chooseFiles)
          .padding(.bottom, 26)
        if !items.isEmpty, let progress {
          LibraryList(
            items: items, jobs: jobsByItem, progress: progress, act: act, delete: delete,
            stop: { item in Task { _ = try? await host.run(CancelJob(item: item.id)) } })
        }
      }
      .padding(.horizontal, 28)
      .padding(.top, 22)
      .padding(.bottom, 60)
    }
    .scrollIndicators(.automatic)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    .navigationTitle(kind.map { Text(Messages.name(of: $0)) } ?? Text(.loci("sidebar.library")))
    .acceptingDrops(opened: opened, failed: failed)
    .subscribing(AllItems(), into: $feed)
    .subscribing(AllJobs(), into: $jobs)
    .task(id: feed?.value?.map(\.id)) { await readProgress() }
  }

  private var shown: [Item] {
    let items = feed?.value ?? []
    guard let kind else { return items }
    return items.filter { ItemKind($0.kind) == kind }
  }

  private var jobsByItem: [EntityID: Job] {
    Dictionary((jobs?.value ?? []).map { ($0.item, $0) }, uniquingKeysWith: { _, latest in latest })
  }

  /// Waits for the list itself: read before it arrives, the progress would be empty, the list would show at once
  /// and the shelf would push it down a moment later.
  private func readProgress() async {
    guard let feed else { return }
    var states: [EntityID: ReadingState] = [:]
    for item in feed.value ?? [] {
      if let state = try? await host.run(ReadReadingState(content: .item(item.id))) { states[item.id] = state }
    }
    progress = Progress(states: states)
  }

  private func add(_ link: URL) {
    Task {
      do throws(HostError) {
        let item = try await host.run(AddLink(url: link))
        opened(WindowState(place: .library(kind), pages: [.item(item.id)]))
      } catch {
        failed(error)
      }
    }
  }

  private func act(_ fix: JobLine.Fix, on item: Item) {
    JobFixes(
      host: host, openPlace: openPlace, browser: browser, failed: ShowFailure(action: failed),
      changesAllowed: changesAllowed
    ).apply(fix, to: item)
  }
}

/// The shelf over the list, scrolled with the page around them.
struct LibraryList: View {
  let items: [Item]
  let jobs: [EntityID: Job]
  let progress: Progress
  let act: (JobLine.Fix, Item) -> Void
  let delete: (Item) -> Void
  let stop: (Item) -> Void
  @Environment(\.controlActiveState) private var active
  @State private var pointing: EntityID?

  /// The row under the pointer, in the window in front only.
  private var hovered: EntityID? { active == .key ? pointing : nil }

  var body: some View {
    let shelf = progress.shelf(of: items)
    VStack(alignment: .leading, spacing: 0) {
      if !shelf.isEmpty {
        ShelfRow(items: shelf, jobs: jobs, progress: progress, act: act)
          .padding(.bottom, 26)
      }
      let rows = items.filter { item in !shelf.contains { $0.id == item.id } }
      ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
        NavigationLink(value: Page.item(item.id)) {
          LibraryRow(item: item, job: jobs[item.id], share: progress.share(of: item)) { act($0, item) }
            .background(
              RoundedRectangle(cornerRadius: Radius.cover, style: .continuous)
                .fill(hovered == item.id ? Palette.fill : .clear)
            )
            .overlay(alignment: .top) {
              if index > 0, hovered != item.id, hovered != rows[index - 1].id {
                Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline)
                  .padding(.leading, Size.listThumbnail + Spacing.xs + 14)
                  .padding(.trailing, Spacing.xs)
              }
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in pointing = inside ? item.id : (pointing == item.id ? nil : pointing) }
        .contextMenu { menu(for: item).changesData() }
      }
    }
  }

  @ViewBuilder private func menu(for item: Item) -> some View {
    if case .working = JobLine(jobs[item.id]) {
      Button {
        stop(item)
      } label: {
        Text(.loci("job.stop"))
      }
    }
    Button(role: .destructive) {
      delete(item)
    } label: {
      Text(.loci("item.delete"))
    }
  }
}

/// Up to three large covers, the first a little wider than the others.
struct ShelfRow: View {
  let items: [Item]
  let jobs: [EntityID: Job]
  let progress: Progress
  let act: (JobLine.Fix, Item) -> Void

  var body: some View {
    GeometryReader { frame in
      let gaps = Size.shelfGap * 2
      let unit = (frame.size.width - gaps) / (Size.shelfLead + 2)
      HStack(spacing: Size.shelfGap) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          NavigationLink(value: Page.item(item.id)) {
            ShelfCover(item: item, share: progress.share(of: item), job: jobs[item.id]) { act($0, item) }
          }
          .buttonStyle(PressStyle())
          .frame(width: index == 0 ? unit * Size.shelfLead : unit)
        }
      }
    }
    .frame(height: Size.shelfHeight)
  }
}

extension EnvironmentValues {
  /// The window's built-in browser.
  @Entry var browser: BrowserSession?
}
