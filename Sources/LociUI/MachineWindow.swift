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
  @State private var items: Feed<[Item]>?
  @State private var health: Feed<Health>?
  @State private var status: Feed<LociStatus>?
  @State private var name: Feed<String>?
  @State private var avatar: Feed<Avatar?>?
  @State private var saving: Feed<SavingBatch?>?
  @State private var dialogs = Dialogs()
  @State private var focusRequest = 0
  @State private var covers = Covers()
  @State private var deletions = Deletions()
  @State private var linkPreviews = LinkPreviews()
  @State private var panelPictures = PanelPictures()
  @State private var browser: BrowserSession
  @State private var nowPlaying = NowPlaying()
  @AppStorage(PaneWidth.sidebar.key) private var sidebarWidth = Double(PaneWidth.sidebar.ideal)
  @AppStorage("sidebarShown") private var sidebarPreferred = true
  @AppStorage("panelColumnShown") private var panelColumnPreferred = true
  @State private var fit = PaneFit.sidebar
  @State private var width = CGFloat.infinity
  private let talkShown: () -> Void
  private let memory: WindowMemory

  /// Opens where `memory` says the window was last, and keeps it told of every move.
  init(talkShown: @escaping () -> Void = {}, memory: WindowMemory, browser: BrowserSession = BrowserSession()) {
    self.talkShown = talkShown
    self.memory = memory
    _browser = State(initialValue: browser)
  }

  var body: some View {
    layout
      .overlay {
        if let pending = dialogs.intake {
          ImportSheet(pending: pending, close: { dialogs.intake = nil }, open: { window = window.opening(.item($0)) })
            .id(pending)
            .transition(.opacity)
        }
      }
      .animation(Motion.standard, value: dialogs.intake)
      .overlay { if (saving?.value ?? nil) != nil { WindowGlow() } }
      .animation(.easeInOut(duration: 0.6), value: (saving?.value ?? nil) != nil)
      .background(WindowButtons(inset: Size.windowButtons))
      .background(WindowKeys(whileTyping: true, handle: key))
      .toolbar(removing: .title)
      .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
      .tint(Palette.accent)
      .frame(minWidth: Size.windowMinimum.width, minHeight: Size.windowMinimum.height)
      .subscribing(AllItems(), into: $items)
      .subscribing(HealthReport(), into: $health)
      .subscribing(CompanionName(), into: $name)
      .subscribing(LociWorking(), into: $status)
      .subscribing(LociModel.LociAvatar(), into: $avatar)
      .subscribing(SavingNow(), into: $saving)
      .onAppear(perform: restore)
      .task { await openModelSetup() }
      .onChange(of: window) { memory.remember(window) }
      .onChange(of: itemIDs) { _, items in
        if let items { window = window.keeping(items: items) }
      }
      .onChange(of: health?.value?.readingStateLost) { _, lost in
        if lost == true { dialogs.readingStateLost = true }
      }
      .focusedSceneValue(\.navigator, navigator)
      .dialogs($dialogs, host: host)
      .environment(\.covers, covers)
      .environment(\.deletions, deletions)
      .environment(\.linkPreviews, linkPreviews)
      .environment(\.panelPictures, panelPictures)
      .environment(\.browser, browser)
      .environment(\.nowPlaying, nowPlaying)
      .environment(\.companionName, name?.value ?? "")
      .environment(\.lociFace, face)
      .environment(\.showFailure, ShowFailure { dialogs.failure = $0 })
      .takingIn(takeIn)
      .lociAppearance()
  }

  /// The sidebar beside the place and the pages over it, with the buttons that float at the top.
  private var layout: some View {
    HStack(spacing: 0) {
      if sidebarShown { sidebar.transition(.move(edge: .leading).combined(with: .opacity)) }
      PageStack(pages: $window.pages) {
        placeView.environment(\.openPlace, openPlace)
      } destination: { page in
        ItemScreen(destination: page).environment(\.openPlace, openPlace)
      }
      .nowPlaying(nowPlaying, items: items?.value ?? [], front: window.pages.last?.itemID) {
        window = window.opening($0)
      }
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      width = $0
    }
    .onChange(of: width) { refit() }
    .onChange(of: reading) { refit() }
    .overlayPreferenceValue(WindowCornerItems.self, alignment: .topLeading) { placeButtons in
      HStack(spacing: Spacing.xxs) {
        if !sidebarShown {
          SidebarToggle(shown: false, toggle: toggleSidebar).glassEffect(.regular, in: .capsule)
        }
        ForEach(window.pages.isEmpty ? placeButtons : [pageBack]) { WindowCornerButton(button: $0) }
      }
      .padding(.leading, sidebarShown ? sidebarEdge + Spacing.s : Size.sidebarToggleLeading)
      .padding(.top, Spacing.xs)
    }
    .ignoresSafeArea(edges: .top)
    .background(Palette.canvas)
    .peekingLinks()
    .environment(\.openPage, OpenPage { window.pages.append($0) })
    .environment(\.openPlace, openPlace)
  }

  /// Closes the page on top and goes back to the one under it, or to the place.
  private var pageBack: WindowCornerItem {
    WindowCornerItem(symbol: Symbols.back, label: .loci("page.back"), shortcut: KeyboardShortcut("[")) {
      window.pages.removeLast()
    }
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

  /// The sidebar's rows, above its foot.
  private var sidebarList: some View {
    Sidebar(
      place: placeBinding, lociChosen: lociChosen, work: status?.value?.work,
      chooseLoci: { window = window.choosingLoci() }
    )
    .safeAreaInset(edge: .top, spacing: 0) {
      SidebarToggle(shown: true, toggle: toggleSidebar)
        .frame(maxWidth: .infinity, minHeight: Size.trafficLights, alignment: .trailing)
        .padding(.trailing, Spacing.xs)
    }
    .safeAreaInset(edge: .bottom, alignment: .leading) {
      HStack {
        HealthIndicator(health: health?.value)
        Spacer(minLength: 0)
        UpdateButton()
      }
      .padding(.horizontal, Spacing.s)
      .padding(.bottom, Spacing.xs)
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

  /// An item is open, with the panel beside it.
  private var reading: Bool {
    !window.pages.isEmpty
  }

  /// The main conversation or Loci's page is on screen, so the sidebar's Loci row is chosen.
  private var lociChosen: Bool {
    window.pages.isEmpty && (window.place == .talk || window.place == .loci)
  }

  /// The face the person chose for Loci, or the drawn one.
  private var face: LociFace {
    guard let chosen = avatar?.value ?? nil, let picture = NSImage(data: chosen.data) else { return .drawn }
    return .picture(picture)
  }

  private func refit() {
    var next = fit
    next.fit(width: width, crowded: reading)
    guard next != fit else { return }
    withAnimation(Motion.fold) { fit = next }
  }

  private var openPlace: OpenPlace {
    OpenPlace { window = WindowState(place: $0) }
  }

  /// The place the sidebar shows as chosen: an item open over the library chooses its category.
  private var placeBinding: Binding<Place> {
    Binding(get: { shownPlace }, set: { window = WindowState(place: $0) })
  }

  private var shownPlace: Place {
    if case .courses = window.place { return .courses(nil) }
    guard case .library = window.place, case .item(let id)? = window.pages.last,
      let item = items?.value?.first(where: { $0.id == id })
    else { return window.place }
    return .library(LibraryCategory(item.kind))
  }

  @ViewBuilder private var placeView: some View {
    switch window.place {
    case .talk:
      TalkScreen(
        focusRequest: focusRequest, attach: { dialogs.importing = true }, opened: { window = $0 },
        failed: { dialogs.failure = $0 }, columnPreferred: $panelColumnPreferred
      )
      .onAppear(perform: talkShown)
    case .loci:
      LociScreen()
    case .library(let category):
      LibraryScreen(
        category: category, chooseFiles: { dialogs.importing = true }, opened: { window = $0 },
        failed: { dialogs.failure = $0 })
    case .browser:
      BrowserScreen(session: browser, failed: { dialogs.failure = $0 })
    case .courses(let open):
      CoursesScreen(open: open)
    case .settings(.general):
      GeneralSettingsPage()
    case .settings(.agents):
      AgentSettingsPage()
    case .settings(.models):
      ModelServicesPage()
    case .settings(.media):
      MediaSettingsPage()
    case .settings(.remote):
      RemoteSettingsPage()
    }
  }

  private var navigator: Navigator {
    Navigator(
      showTalk: {
        window = WindowState()
        focusRequest += 1
      },
      showLibrary: { window = WindowState(place: .library(nil)) },
      showSettings: { window = WindowState(place: .settings(.general)) },
      toggleSidebar: toggleSidebar,
      addFile: changesAllowed ? { dialogs.importing = true } : nil,
      pasteLink: linkPaste.map { paste in { _ = paste() } })
  }

  private func key(_ event: NSEvent) -> Bool {
    if window.place == .browser, window.pages.isEmpty,
      browser.handle(event, closeWindow: { event.window?.performClose(nil) })
    {
      return true
    }
    guard !KeyMonitor.isTyping(into: event.window?.firstResponder), LinkPasteKey.isPaste(event) else { return false }
    return pasteInvite() || linkPaste?() == true
  }

  /// What ⌘V does with a link where the window takes one.
  private var linkPaste: (@MainActor () -> Bool)? {
    takesLinks ? pasteLink : nil
  }

  /// The main conversation and the library take a pasted link, but not a page opened over them, and not
  /// while the Mac behind the window is offline.
  private var takesLinks: Bool {
    guard window.pages.isEmpty, changesAllowed else { return false }
    switch window.place {
    case .talk, .library: return true
    case .loci, .browser, .settings, .courses: return false
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

  /// Takes in the link on the pasteboard, staying on the page. Whether there was one.
  private func pasteLink() -> Bool {
    guard let url = PastedLink.on(.general) else { return false }
    takeIn.link(url)
    return true
  }

  private var takeIn: TakeIn {
    TakeIn(host: host, ask: { dialogs.intake = $0 }, failed: { dialogs.failure = $0 })
  }

  /// The items there are, once the list has arrived.
  private var itemIDs: Set<EntityID>? {
    items?.value.map { Set($0.map(\.id)) }
  }

  private func openModelSetup() async {
    guard let access = await host.modelSettingsAccess(), await access.needsModelSetup(),
      !Task.isCancelled, window == WindowState()
    else { return }
    window = WindowState(place: .settings(.models))
  }

  /// Opens where the window was last, unless that was an item deleted since; the list of items may arrive
  /// before or after.
  private func restore() {
    guard !restored else { return }
    restored = true
    let recalled = memory.recall()
    window = itemIDs.map(recalled.keeping(items:)) ?? recalled
  }
}
