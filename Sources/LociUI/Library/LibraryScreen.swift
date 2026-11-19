import AppKit
import LociModel
import SwiftUI

/// The library: the link field, what is being watched on a shelf of large covers, and every item in a list
/// below with the work on it. Pasting or dropping a link adds it too. Items are renamed in place, given a new
/// cover, and deleted with a notice that brings them back.
struct LibraryScreen: View {
  @Environment(\.host) private var host
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.openPlace) private var openPlace
  @Environment(\.browser) private var browser
  @Environment(\.covers) private var covers
  @Environment(\.choosePicture) private var choosePicture
  @Environment(\.undoManager) private var undoManager
  let kind: ItemKind?
  let chooseFiles: () -> Void
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @State private var feed: Feed<[Item]>?
  @State private var jobs: Feed<[Job]>?
  /// Read once before the list shows, so the shelf does not push the list down after it appears.
  @State private var progress: Progress?
  @State private var selection = LibrarySelection()
  @State private var renaming: EntityID?
  @State private var deletion: Deletion?
  @State private var undoTarget = UndoTarget()

  /// The latest deletion, while it can still be undone from the notice.
  struct Deletion: Equatable {
    let id = UUID()
    let count: Int
  }

  final class UndoTarget {}

  var body: some View {
    let items = shown
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        LinkField(kind: kind, add: add, chooseFiles: chooseFiles)
          .padding(.bottom, 26)
        if !items.isEmpty, let progress {
          LibraryList(
            items: items, jobs: jobsByItem, progress: progress, chosen: selection.chosen, renaming: renaming,
            click: { click($0, in: items, progress: progress) }, act: act, actions: actions,
            acted: selection.acted(on:), renamed: rename)
        }
      }
      .padding(.horizontal, 28)
      .padding(.top, 22)
      .padding(.bottom, 60)
    }
    .scrollIndicators(.automatic)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    .overlay(alignment: .bottom) {
      if let deletion {
        DeletedNotice(count: deletion.count, undo: undo)
          .padding(.bottom, 24)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(Motion.standard, value: deletion)
    .background(WindowKeys(handle: key))
    .navigationTitle(kind.map { Text(Messages.name(of: $0)) } ?? Text(.loci("sidebar.library")))
    .acceptingDrops(opened: opened, failed: failed)
    .subscribing(AllItems(), into: $feed)
    .subscribing(AllJobs(), into: $jobs)
    .task(id: feed?.value?.map(\.id)) { await readProgress() }
    .onChange(of: items.map(\.id)) { selection.keep(items.map(\.id)) }
    .task(id: deletion) {
      guard deletion != nil else { return }
      try? await Task.sleep(for: .seconds(6))
      if !Task.isCancelled { deletion = nil }
    }
  }

  private var shown: [Item] {
    let items = feed?.value ?? []
    guard let kind else { return items }
    return items.filter { ItemKind($0.kind) == kind }
  }

  private var jobsByItem: [EntityID: Job] {
    Dictionary((jobs?.value ?? []).map { ($0.item, $0) }, uniquingKeysWith: { _, latest in latest })
  }

  private var actions: ItemActions {
    ItemActions(
      rename: { renaming = $0.id }, changeCover: changeCover, delete: delete,
      stop: { item in Task { _ = try? await host.run(CancelJob(item: item.id)) } })
  }

  private func click(_ item: EntityID, in items: [Item], progress: Progress) {
    let order = LibraryList.order(of: items, progress: progress).map(\.id)
    let click = LibrarySelection.Click(NSEvent.modifierFlags)
    if selection.click(item, click, in: order) {
      opened(WindowState(place: .library(kind), pages: [.item(item)]))
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

  private func act(_ fix: JobLine.Fix, on item: Item) {
    JobFixes(
      host: host, openPlace: openPlace, browser: browser, failed: ShowFailure(action: failed),
      changesAllowed: changesAllowed
    ).apply(fix, to: item)
  }

  private func add(_ link: URL) {
    run { () async throws(HostError) in
      let item = try await host.run(AddLink(url: link))
      opened(WindowState(place: .library(kind), pages: [.item(item.id)]))
    }
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
      if let image = NSImage(contentsOf: picture) { covers?.replace(item.id, with: image) }
    }
  }

  private func delete(_ items: [EntityID]) {
    run { () async throws(HostError) in
      _ = try await host.run(DeleteItems(items))
      selection.clear()
      deletion = Deletion(count: items.count)
      undoManager?.removeAllActions(withTarget: undoTarget)
      undoManager?.registerUndo(withTarget: undoTarget) { _ in
        MainActor.assumeIsolated { undo() }
      }
      undoManager?.setActionName(String(localized: .loci("item.delete")))
    }
  }

  private func undo() {
    undoManager?.removeAllActions(withTarget: undoTarget)
    deletion = nil
    run { () async throws(HostError) in _ = try await host.run(RestoreDeleted()) }
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
