import AppKit
import LociModel
import SwiftUI

/// The library: the link field over every item, and floating at its foot the task dock while
/// there is work. Pasting or dropping a link adds it too. Items are renamed in place, given a new cover, and
/// deleted with a notice that brings them back; cancelling an item's work deletes it the same way.
struct LibraryScreen: View {
  @Environment(\.host) private var host
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.openPlace) private var openPlace
  @Environment(\.browser) private var browser
  @Environment(\.covers) private var covers
  @Environment(\.choosePicture) private var choosePicture
  @Environment(\.undoManager) private var undoManager
  @Environment(\.takeIn) private var takeIn
  @Environment(\.deletions) private var deletions
  @Environment(\.standIns) private var standIns
  let category: LibraryCategory?
  let chooseFiles: () -> Void
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @State private var feed: Feed<[Item]>?
  @State private var jobs: Feed<[Job]>?
  @State private var saving: Feed<SavingBatch?>?
  @State private var storage: Feed<StorageReport>?
  @State private var progress = Progress()
  @State private var selection = LibrarySelection()
  @State private var renaming: EntityID?
  @AppStorage(LibraryPresentation.key) private var presentation = LibraryPresentation.gallery

  var body: some View {
    let items = shown
    let itemIDs = items.map(\.id)
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        controls.padding(.bottom, presentation == .gallery ? 26 : 12)
        if !items.isEmpty {
          LibraryEntries(
            items: items, jobs: jobsByItem, progress: progress, chosen: selection.chosen, renaming: renaming,
            click: { click($0, in: items) }, actions: cardActions,
            menu: { menu(for: $0) }, renamed: rename, presentation: presentation)
        }
      }
      .padding(.horizontal, 28)
      .padding(.top, 22)
      .padding(.bottom, 28)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Color.clear.frame(height: TaskDock.arrange(jobs?.value ?? []) == nil ? 0 : TaskDock.room)
    }
    .defaultScrollAnchor(standIns?.galleryAtEnd == true ? .bottom : .top)
    .scrollIndicators(.automatic)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    .overlay(alignment: .bottom) {
      VStack(spacing: 10) {
        if let deletion = deletions?.latest {
          DeletedNotice(count: deletion.count) { deletions?.undo() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        TaskDock(
          jobs: jobs?.value ?? [],
          items: Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
          saving: saving?.value ?? nil, actions: DockActions(card: cardActions, stopSaving: stopSaving))
      }
      .padding(.bottom, 20)
    }
    .animation(Motion.standard, value: deletions?.latest)
    .background(WindowKeys(handle: key))
    .navigationTitle(category.map { Text(Messages.name(of: $0)) } ?? Text(.loci("sidebar.library")))
    .acceptingDrops()
    .subscribing(AllItems(), into: $feed)
    .subscribing(AllJobs(), into: $jobs)
    .subscribing(SavingNow(), into: $saving)
    .subscribing(StorageUse(), into: $storage)
    .task(id: itemIDs) { await readProgress(itemIDs) }
    .onChange(of: itemIDs) { selection.keep(itemIDs) }
    .task(id: deletions?.latest) {
      guard let deletion = deletions?.latest else { return }
      try? await Task.sleep(for: .seconds(6))
      if !Task.isCancelled { deletions?.settle(deletion) }
    }
  }

  private var controls: some View {
    HStack(spacing: Spacing.m) {
      LinkField(category: category, add: add, chooseFiles: chooseFiles)
      Picker(selection: $presentation) {
        ForEach(LibraryPresentation.allCases, id: \.self) { option in
          Label {
            Text(option.name)
          } icon: {
            Image(systemName: option.symbol)
          }
          .labelStyle(.iconOnly)
          .tag(option)
        }
      } label: {
        Text(.loci("library.presentation"))
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .controlSize(.large)
      .fixedSize()
    }
  }

  private var shown: [Item] {
    let items = feed?.value ?? []
    guard let category else { return items }
    return items.filter { LibraryCategory($0.kind) == category }
  }

  private var jobsByItem: [EntityID: Job] {
    Dictionary((jobs?.value ?? []).map { ($0.item, $0) }, uniquingKeysWith: { _, latest in latest })
  }

  private var actions: ItemActions {
    ItemActions(
      rename: { renaming = $0.id }, changeCover: changeCover, delete: delete,
      freeSpace: { item in run { () async throws(HostError) in _ = try await host.run(FreeMediaSpace(item: item.id)) }
      },
      saveLocally: { item in
        run { () async throws(HostError) in _ = try await host.run(SaveMediaLocally(item: item.id)) }
      })
  }

  /// Freeing space or saving again is offered while no work is going on.
  private func menu(for item: Item) -> ItemMenu {
    let quiet = !CardState(jobsByItem[item.id]).isBusy
    let space = quiet ? storage?.value?.items.first { $0.item == item.id } : nil
    return ItemMenu(item: item, acted: selection.acted(on: item.id), actions: actions, space: space)
  }

  private var cardActions: CardActions {
    CardActions(
      pause: { item in run { () async throws(HostError) in _ = try await host.run(PauseJob(item: item.id)) } },
      resume: { item in run { () async throws(HostError) in _ = try await host.run(RetryJob(item: item.id)) } },
      cancel: { delete([$0.id]) }, fix: act)
  }

  private func click(_ item: EntityID, in items: [Item]) {
    let click = LibrarySelection.Click(event: NSApp.currentEvent)
    if selection.click(item, click, in: items.map(\.id)) {
      opened(WindowState(place: .library(category), pages: [.item(item)]))
    }
  }

  /// ⌘⌫ deletes the chosen items; Escape lets go of them.
  private func key(_ event: NSEvent) -> Bool {
    guard !selection.chosen.isEmpty else { return false }
    if event.specialKey == .delete, KeyMonitor.modifiers(of: event) == .command, changesAllowed {
      delete(Array(selection.chosen))
      return true
    }
    if event.charactersIgnoringModifiers == "\u{1B}" {
      selection.clear()
      return true
    }
    return false
  }

  /// The saved reading state of the items in the current view.
  private func readProgress(_ items: [EntityID]) async {
    var states: [EntityID: ReadingState] = [:]
    for item in items {
      guard !Task.isCancelled else { return }
      if let state = try? await host.run(ReadReadingState(content: .item(item))) { states[item] = state }
    }
    if !Task.isCancelled { progress = Progress(states: states) }
  }

  private func act(_ fix: JobLine.Fix, on item: Item) {
    JobFixes(
      host: host, openPlace: openPlace, browser: browser, failed: ShowFailure(action: failed),
      changesAllowed: changesAllowed
    ).apply(fix, to: item)
  }

  private func add(_ link: URL) {
    takeIn?.link(link)
  }

  private func rename(_ item: Item, to title: String?) {
    renaming = nil
    guard let title else { return }
    run { () async throws(HostError) in _ = try await host.run(RenameItem(item: item.id, title: title)) }
  }

  private func changeCover(_ item: Item) {
    run { () async throws(HostError) in
      guard let picture = await choosePicture() else { return }
      _ = try await host.run(SetCover(item: item.id, upload: try await host.upload(LocalFile(picture))))
      covers?.invalidate(item.id)
    }
  }

  private func delete(_ items: [EntityID]) {
    run { () async throws(HostError) in
      _ = try await host.run(DeleteItems(items))
      deleted(items.count)
    }
  }

  /// Loci's batch stops: what had not started goes, with the notice that brings it back.
  private func stopSaving() {
    run { () async throws(HostError) in
      let count = try await host.run(StopSaving())
      if count > 0 { deleted(count) }
    }
  }

  private func deleted(_ count: Int) {
    selection.clear()
    deletions?.happened(count, undoManager: undoManager) {
      run { () async throws(HostError) in _ = try await host.run(RestoreDeleted()) }
    }
  }

  private func run(_ work: @escaping @MainActor () async throws(HostError) -> Void) {
    Task {
      do throws(HostError) {
        try await work()
      } catch {
        failed(error)
      }
    }
  }
}

extension EnvironmentValues {
  /// The window's built-in browser.
  @Entry var browser: BrowserSession?
}
