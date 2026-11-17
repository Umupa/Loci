import LociModel
import SwiftUI
import UniformTypeIdentifiers

/// The content of a Loci window: the sidebar, and whatever it has selected.
public struct RootView: View {
  @Environment(\.host) private var host
  @SceneStorage("window") private var stored = ""
  @State private var window = WindowState()
  @State private var restored = false
  @State private var mentors: Feed<[Mentor]>?
  @State private var items: Feed<[Item]>?
  @State private var health: Feed<Health>?
  @State private var dialogs = Dialogs()
  @State private var focusRequest = 0
  private let startShown: () -> Void
  private let opening: WindowState

  /// `startShown` runs when the start page first appears, which is when Loci can be typed into.
  public init(startShown: @escaping () -> Void = {}) {
    self.init(startShown: startShown, opening: WindowState())
  }

  /// Opens at `opening` unless the window has a place of its own to return to.
  init(startShown: @escaping () -> Void = {}, opening: WindowState) {
    self.startShown = startShown
    self.opening = opening
  }

  public var body: some View {
    NavigationSplitView {
      Sidebar(
        place: placeBinding, mentors: mentors?.value ?? [], kinds: ItemKind.present(in: items?.value ?? []),
        rename: { dialogs.rename($0) }, delete: { dialogs.deletingMentor = $0 }
      )
      .navigationSplitViewColumnWidth(min: Size.sidebarMinimum, ideal: Size.sidebarIdeal)
    } detail: {
      NavigationStack(path: $window.pages) {
        placeView
          .navigationDestination(for: Page.self) { pageView($0) }
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
    .onChange(of: window) { stored = window.text }
    .onChange(of: mentors?.value.map { Set($0.map(\.id)) }) { _, known in
      if let known { window = window.keeping(mentors: known) }
    }
    .onChange(of: health?.value?.readingStateLost) { _, lost in
      if lost == true { dialogs.readingStateLost = true }
    }
    .focusedSceneValue(\.navigator, navigator)
    .dialogs($dialogs, host: host)
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
    window = stored.isEmpty ? opening : WindowState(restoring: stored)
  }
}

extension View {
  /// Gives the views inside the host they read from and send commands to.
  public func lociHost(_ host: any LociModel.Host) -> some View {
    environment(\.host, host)
  }
}
