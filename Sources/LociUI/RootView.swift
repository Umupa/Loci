import LociModel
import SwiftUI
import UniformTypeIdentifiers

/// The content of a Loci window: the sidebar, and whatever it has selected.
public struct RootView: View {
  @Environment(\.host) private var host
  @State private var window = WindowState()
  @State private var restored = false
  @State private var mentors: Feed<[Mentor]>?
  @State private var items: Feed<[Item]>?
  @State private var health: Feed<Health>?
  @State private var dialogs = Dialogs()
  @State private var focusRequest = 0
  private let startShown: () -> Void
  private let memory: WindowMemory

  /// `folder` is the data folder the host serves, so each folder reopens where it was left. `startShown`
  /// runs when the start page first appears, which is when Loci can be typed into.
  public init(folder: URL, startShown: @escaping () -> Void = {}) {
    self.init(startShown: startShown, memory: .preferences(.standard, folder: folder))
  }

  /// Opens where `memory` says the window was last, and keeps it told of every move.
  init(startShown: @escaping () -> Void = {}, memory: WindowMemory) {
    self.startShown = startShown
    self.memory = memory
  }

  public var body: some View {
    NavigationSplitView {
      Sidebar(
        place: placeBinding, mentors: mentors?.value ?? [], kinds: ItemKind.present(in: items?.value ?? []),
        rename: { dialogs.rename($0) }, configure: { dialogs.configuring = $0 }, delete: { dialogs.deletingMentor = $0 }
      )
      .navigationSplitViewColumnWidth(min: Size.sidebarMinimum, ideal: Size.sidebarIdeal)
    } detail: {
      PageStack(pages: $window.pages) {
        placeView
      } destination: {
        pageView($0)
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) { HealthIndicator(health: health?.value) }
    }
    .tint(Palette.accent)
    .frame(minWidth: Size.windowMinimum.width, minHeight: Size.windowMinimum.height)
    .subscribing(AllMentors(), into: $mentors)
    .subscribing(AllItems(), into: $items)
    .subscribing(HealthReport(), into: $health)
    .onAppear(perform: restore)
    .onChange(of: window) { memory.remember(window) }
    .onChange(of: known) { _, known in
      if let known { window = window.keeping(mentors: known.mentors, items: known.items) }
    }
    .onChange(of: health?.value?.readingStateLost) { _, lost in
      if lost == true { dialogs.readingStateLost = true }
    }
    .focusedSceneValue(\.navigator, navigator)
    .dialogs($dialogs, host: host)
  }

  /// What exists, once both lists have arrived.
  private var known: Known? {
    guard let mentors = mentors?.value, let items = items?.value else { return nil }
    return Known(mentors: Set(mentors.map(\.id)), items: Set(items.map(\.id)))
  }

  private struct Known: Equatable {
    let mentors: Set<EntityID>
    let items: Set<EntityID>
  }

  private var placeBinding: Binding<Place> {
    Binding(get: { window.place }, set: { window = WindowState(place: $0) })
  }

  @ViewBuilder private var placeView: some View {
    switch window.place {
    case .start:
      StartPage(focusRequest: focusRequest, opened: { window = $0 }, failed: { dialogs.failure = $0 })
        .onAppear(perform: startShown)
    case .mentor(let id):
      MentorScreen(mentor: id)
    case .library(let kind):
      LibraryScreen(
        kind: kind, opened: { window = $0 }, failed: { dialogs.failure = $0 }, delete: { dialogs.deletingItem = $0 })
    }
  }

  @ViewBuilder private func pageView(_ page: Page) -> some View {
    switch page {
    case .lesson(let lesson): LessonScreen(lesson: lesson)
    case .item(let item): ItemScreen(item: item)
    }
  }

  private var navigator: Navigator {
    Navigator(
      showStart: {
        window = WindowState()
        focusRequest += 1
      },
      showLibrary: { window = WindowState(place: .library(nil)) },
      addFile: { dialogs.importing = true })
  }

  private func restore() {
    guard !restored else { return }
    restored = true
    window = memory.recall()
  }
}

extension View {
  /// Gives the views inside the host they read from and send commands to.
  public func lociHost(_ host: any LociModel.Host) -> some View {
    environment(\.host, host)
  }
}
