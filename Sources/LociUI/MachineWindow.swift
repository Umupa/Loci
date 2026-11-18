import LociModel
import SwiftUI
import UniformTypeIdentifiers

/// One Mac's data in the window: the sidebar, and whatever it has selected.
struct MachineWindow: View {
  @Environment(\.host) private var host
  @Environment(\.machineChoice) private var machineChoice
  @Environment(\.changesAllowed) private var changesAllowed
  @State private var window = WindowState()
  @State private var restored = false
  @State private var mentors: Feed<[Mentor]>?
  @State private var items: Feed<[Item]>?
  @State private var health: Feed<Health>?
  @State private var dialogs = Dialogs()
  @State private var focusRequest = 0
  @State private var covers = Covers()
  @State private var browser: BrowserSession
  @AppStorage(PaneWidth.sidebar.key) private var sidebarWidth = Double(PaneWidth.sidebar.ideal)
  @AppStorage("sidebarShown") private var sidebarPreferred = true
  @State private var fit = SidebarFit()
  @State private var width = CGFloat.infinity
  private let startShown: () -> Void
  private let memory: WindowMemory

  /// Opens where `memory` says the window was last, and keeps it told of every move.
  init(startShown: @escaping () -> Void = {}, memory: WindowMemory, browser: BrowserSession = BrowserSession()) {
    self.startShown = startShown
    self.memory = memory
    _browser = State(initialValue: browser)
  }

  var body: some View {
    layout
      .background(WindowButtons(inset: Size.windowButtons))
      .background(LinkPasteKey(paste: keyPaste))
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
      .environment(\.covers, covers)
      .environment(\.browser, browser)
      .environment(\.showFailure, ShowFailure { dialogs.failure = $0 })
      .lociAppearance()
  }

  /// The sidebar beside the place and the pages over it, with the buttons that float at the top.
  private var layout: some View {
    HStack(spacing: 0) {
      if sidebarShown { sidebar.transition(.move(edge: .leading).combined(with: .opacity)) }
      PageStack(pages: $window.pages) {
        placeView.environment(\.openPlace, openPlace)
      } destination: {
        pageView($0).environment(\.openPlace, openPlace)
      }
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      width = $0
    }
    .onChange(of: width) { refit() }
    .onChange(of: reading) { refit() }
    .overlay(alignment: .topLeading) {
      HStack(spacing: Spacing.xxs) {
        if !sidebarShown {
          SidebarToggle(shown: false, toggle: toggleSidebar).glassEffect(.regular, in: .capsule)
        }
        if !window.pages.isEmpty {
          PageBack { window.pages.removeLast() }
        }
      }
      .padding(.leading, sidebarShown ? sidebarEdge + Spacing.s : Size.sidebarToggleLeading)
      .padding(.top, Spacing.xs)
    }
    .ignoresSafeArea(edges: .top)
    .background(Palette.canvas)
  }

  private var sidebar: some View {
    VStack(spacing: 0) {
      sidebarList
      MachineFoot()
    }
    .frame(width: PaneWidth.sidebar.clamped(sidebarWidth))
    .background(Palette.sidebarWash, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .padding(Spacing.xs)
    .overlay(alignment: .trailing) { PaneResizer(pane: .sidebar, width: $sidebarWidth) }
  }

  /// The sidebar's list, which scrolls above its foot.
  private var sidebarList: some View {
    Sidebar(
      place: placeBinding, openLesson: openLesson, mentors: mentors?.value ?? [],
      kinds: ItemKind.listed(in: items?.value ?? []),
      rename: { dialogs.rename($0) }, delete: { dialogs.deletingMentor = $0 }
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
  }

  /// Where the sidebar's floating card ends.
  private var sidebarEdge: CGFloat {
    PaneWidth.sidebar.clamped(sidebarWidth) + Spacing.xs * 2
  }

  private var sidebarShown: Bool { fit.shows(sidebarPreferred) }

  private func toggleSidebar() {
    withAnimation(Motion.fold) { sidebarPreferred = fit.toggle(sidebarPreferred) }
  }

  /// A lesson or an item is open, with the panel beside its text.
  private var reading: Bool {
    switch window.pages.last {
    case .lesson, .item: return true
    case nil:
      if case .lesson = window.place { return true }
      return false
    }
  }

  private func refit() {
    var next = fit
    next.fit(width: width, reading: reading)
    guard next != fit else { return }
    withAnimation(Motion.fold) { fit = next }
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

  /// The place the sidebar shows as chosen: an item open over the library chooses its kind.
  private var placeBinding: Binding<Place> {
    Binding(get: { shownPlace }, set: { window = WindowState(place: $0) })
  }

  private var shownPlace: Place {
    guard case .library = window.place, case .item(let id)? = window.pages.last,
      let item = items?.value?.first(where: { $0.id == id })
    else { return window.place }
    return .library(ItemKind(item.kind))
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
    case .browser:
      BrowserScreen(session: browser, opened: { window = $0 }, failed: { dialogs.failure = $0 })
    case .settings(.general):
      GeneralSettingsPage()
    case .settings(.agents):
      AgentSettingsPage()
    case .settings(.media):
      MediaSettingsPage()
    case .settings(.remote):
      RemoteSettingsPage()
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
      addFile: changesAllowed ? { dialogs.importing = true } : nil,
      pasteLink: linkPaste.map { paste in { _ = paste() } })
  }

  /// What ⌘V does: an invite link pairs from any page; another link is added where the window takes one.
  private var keyPaste: @MainActor () -> Bool {
    { pasteInvite() || linkPaste?() == true }
  }

  /// What ⌘V does with a link where the window takes one.
  private var linkPaste: (@MainActor () -> Bool)? {
    takesLinks ? pasteLink : nil
  }

  /// The start page and the library take a pasted link, but not a page opened over them, and not while the
  /// Mac behind the window is offline.
  private var takesLinks: Bool {
    guard window.pages.isEmpty, changesAllowed else { return false }
    switch window.place {
    case .start, .library: return true
    case .lesson, .mentor, .browser, .settings: return false
    }
  }

  /// Pairs with the Mac whose invite link is on the pasteboard. Whether there was one.
  private func pasteInvite() -> Bool {
    guard let accept = machineChoice?.acceptInvite, let text = NSPasteboard.general.string(forType: .string),
      let invite = Invite(pasted: text)
    else { return false }
    accept(invite)
    return true
  }

  /// Adds the link on the pasteboard and opens it. Whether there was one.
  private func pasteLink() -> Bool {
    guard let url = PastedLink.on(.general) else { return false }
    Task { _ = await host.addLink(url, opened: { window = $0 }, failed: { dialogs.failure = $0 }) }
    return true
  }

  private func restore() {
    guard !restored else { return }
    restored = true
    window = memory.recall()
  }
}
