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
  @AppStorage(PaneWidth.sidebar.key) private var sidebarWidth = Double(PaneWidth.sidebar.ideal)
  @AppStorage("sidebarShown") private var sidebarShown = true
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
    HStack(spacing: 0) {
      if sidebarShown { sidebar.transition(.move(edge: .leading).combined(with: .opacity)) }
      PageStack(pages: $window.pages) {
        placeView.environment(\.openPlace, openPlace)
      } destination: {
        pageView($0).environment(\.openPlace, openPlace)
      }
    }
    .overlay(alignment: .topLeading) {
      if !sidebarShown {
        SidebarToggle(shown: false, toggle: toggleSidebar)
          .glassEffect(.regular, in: .capsule)
          .padding(.leading, Size.sidebarToggleLeading)
          .padding(.top, Spacing.xs)
      }
    }
    .ignoresSafeArea(edges: .top)
    .background(Palette.canvas)
    .background(WindowButtons(inset: Size.windowButtons))
    .toolbar(removing: .title)
    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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
    .lociAppearance()
  }

  private var sidebar: some View {
    Sidebar(
      place: placeBinding, openLesson: openLesson, mentors: mentors?.value ?? [],
      kinds: ItemKind.present(in: items?.value ?? []), rename: { dialogs.rename($0) },
      delete: { dialogs.deletingMentor = $0 }
    )
    .scrollContentBackground(.hidden)
    .safeAreaInset(edge: .top, spacing: 0) {
      SidebarToggle(shown: true, toggle: toggleSidebar)
        .frame(maxWidth: .infinity, minHeight: Size.trafficLights, alignment: .trailing)
        .padding(.trailing, Spacing.xs)
    }
    .safeAreaInset(edge: .bottom, alignment: .leading) {
      HealthIndicator(health: health?.value).padding(.horizontal, Spacing.s).padding(.bottom, Spacing.xs)
    }
    .frame(width: PaneWidth.sidebar.clamped(sidebarWidth))
    .background(Palette.sidebarWash, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .padding(Spacing.xs)
    .overlay(alignment: .trailing) { PaneResizer(pane: .sidebar, width: $sidebarWidth) }
  }

  private func toggleSidebar() {
    withAnimation(Motion.fold) { sidebarShown.toggle() }
  }

  private var openPlace: OpenPlace {
    OpenPlace { window = WindowState(place: $0) }
  }

  /// The lesson on screen: a page opened over the place, or the place itself.
  private var openLesson: LessonRef? {
    for page in window.pages.reversed() {
      if case .lesson(let lesson) = page { return lesson }
    }
    if case .lesson(let lesson) = window.place { return lesson }
    return nil
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
    case .lesson(let lesson):
      LessonScreen(lesson: lesson)
    case .mentor(let id):
      MentorScreen(mentor: id)
    case .library(let kind):
      LibraryScreen(
        kind: kind, opened: { window = $0 }, failed: { dialogs.failure = $0 }, delete: { dialogs.deletingItem = $0 })
    case .settings(.general):
      GeneralSettingsPage()
    case .settings(.agents):
      AgentSettingsPage()
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
      showSettings: { window = WindowState(place: .settings(.general)) },
      toggleSidebar: toggleSidebar,
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
