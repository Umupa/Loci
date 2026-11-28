import LociModel
import SwiftUI

/// The companion's page: who it is in the top-left corner, and the project bar over the chat or the project it
/// has open, or over a new project's page. The open one is remembered for the Mac. A next-up card started from
/// the deck flies into its seal, and its project opens; so does a new project's large seal once its words are
/// sent.
struct CompanionPage: View {
  @Environment(\.host) private var host
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.cardDelivery) private var cardDelivery
  @Environment(\.machineChoice) private var machineChoice
  @Environment(\.documents) private var documents
  /// Changes each time the chat itself should come to the front, from whichever project was open.
  var chatRequest = 0
  let focusRequest: Int
  let attach: () -> Void
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @Binding var columnPreferred: Bool
  let memory: WindowMemory
  let visits: ConversationVisits
  /// Opens on a new project's page, for a snapshot.
  var opening: NewProjectDraft?
  @State private var project: Project.ID?
  @State private var recalled = false
  @State private var bar: Feed<ProjectBar>?
  @State private var draft: NewProjectDraft?
  /// A new project's page put away, still sliding out.
  @State private var parting: NewProjectDraft?
  /// The project last made from a new project's page, which takes that page's place.
  @State private var handed: Project.ID?
  /// Counts the times the page in front was put there at once instead of turned to.
  @State private var jumps = 0
  @State private var launching: Launching?
  @State private var sealFrame = CGRect.zero
  /// The symbols new projects' words suggested, worn faintly until they are named.
  @State private var suggested: [Project.ID: String] = [:]
  @State private var notice: Notice?
  @State private var focusedCard: EntityID?
  @State private var nextUps: Feed<[NextUp]>?
  @State private var flight: NextUp?
  /// How many cards each seal caught, to stamp it once more.
  @State private var stamps: [Home: Int] = [:]
  /// Asks a home's input field for the keyboard when its page comes to the front; pages stay made behind it.
  @State private var focus: [Home: Int] = [:]
  /// The projects whose pages stay made while another home shows, the latest opened last.
  @State private var madeProjects: [Project.ID] = []
  @State private var pageWidth: CGFloat = 0
  @State private var homeSwitch = HomeSwitch.logged()
  /// The chat's layout, for the layout button over a new project's field.
  @AppStorage(TalkLayout.key) private var storedLayout = Data()

  /// A new project's words on their way: the large seal flies into the bar while the project is made, and the
  /// project opens once both are done.
  struct Launching: Equatable {
    let symbol: String?
    let from: CGRect
    var landed: Bool
    var project: Project.ID?
  }

  /// Where things on the page are, for a seal to fly between them.
  nonisolated static let space = "companion"

  /// What the last archiving, deletion, or card put off or declined took away, to undo.
  enum Notice: Equatable {
    case archived(Project.ID, serial: UUID = UUID())
    case deleted(serial: UUID = UUID())
    /// The card as it was put off or declined, to bring back if it is still so.
    case card(NextUp, later: Bool, serial: UUID = UUID())
  }

  private var home: Home { project.map(Home.project) ?? .chat }

  private var chatLayout: Binding<TalkLayout> {
    Binding(
      get: { (try? JSONDecoder().decode(TalkLayout.self, from: storedLayout)) ?? .standard },
      set: { storedLayout = (try? JSONEncoder().encode($0)) ?? storedLayout })
  }
  private var shownBar: ProjectBar { bar?.value ?? ProjectBar(projects: []) }

  var body: some View {
    ZStack(alignment: .top) {
      SlidingPages(
        front: draft == nil ? .home(home) : .newProject, order: HomeSlide.order(of: shownBar), kept: keptProjects,
        newProject: (draft ?? parting) != nil, handed: handed, jump: jumps, swipes: documents?.shown == nil,
        open: { open($0, made: true) }, settled: { if draft == nil { parting = nil } }
      ) { page in
        switch page {
        case .home(let pageHome): talk(pageHome)
        case .newProject: newProjectPage
        }
      }
      CompanionBar(
        bar: shownBar, home: home, pageWidth: pageWidth, newSeal: newSeal, suggested: suggested, stamps: stamps,
        actions: actions)
    }
    .coordinateSpace(.named(Self.space))
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      pageWidth = $0
    }
    .overlayPreferenceValue(NextUpAnchors.self) { anchors in
      GeometryReader { proxy in
        if let flight {
          if let from = anchors.cards[flight.id], let to = anchors.seals[flight.home] {
            CardFlight(card: flight, project: project(of: flight), from: proxy[from], to: proxy[to]) {
              land(flight)
            }
          } else {
            Color.clear.onAppear { land(flight) }
          }
        }
        if let launching, !launching.landed, let to = anchors.newSeal {
          SealFlight(symbol: launching.symbol, from: launching.from, to: proxy[to]) {
            self.launching?.landed = true
            settle()
          }
        }
      }
    }
    .overlay(alignment: .bottom) {
      if let notice {
        DeletedNotice(words: words(of: notice)) { undo(notice) }
          .changesData()
          .padding(.bottom, 84)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(reduceMotion ? nil : Motion.standard, value: notice)
    .animation(reduceMotion ? nil : Motion.standard, value: draft == nil)
    .subscribing(WatchProjects(), into: $bar)
    .subscribing(WatchNextUps(of: home), into: $nextUps)
    .onChange(of: home) {
      nextUps = nil
      timing?.shown(home)
    }
    .onDisappear { timing?.left() }
    .environment(\.homeSwitch, timing)
    .onChange(of: shownHome) { if let shownHome { focus[shownHome, default: 0] += 1 } }
    .onChange(of: focusRequest) { if let shownHome { focus[shownHome, default: 0] += 1 } }
    .onChange(of: chatRequest) { actions.open(.chat) }
    .onAppear {
      guard !recalled else { return }
      recalled = true
      project = cardDelivery?.waiting.map { $0.home.project } ?? memory.recallProject()
      if let opening { draft = opening }
      jumps += 1
    }
    .onChange(of: project) {
      memory.rememberProject(project)
      madeProjects = keptProjects
    }
    .onChange(of: bar?.value) {
      settle()
      openNotifiedCard()
    }
    .onChange(of: cardDelivery?.waiting, initial: true) { openNotifiedCard() }
    .task(id: notice) {
      guard let shown = notice else { return }
      try? await Task.sleep(for: .seconds(6))
      if !Task.isCancelled, notice == shown { notice = nil }
    }
  }

  /// A home's conversation and panels. The chat's page and those of the last projects opened stay made while
  /// another home shows, so going back to one shows it as it was instead of making it again. What a page is
  /// given does not depend on which home shows, so turning between them leaves the pages behind untouched.
  private func talk(_ pageHome: Home) -> some View {
    let shown = pageHome == shownHome
    let project = pageHome.project.flatMap { projectsMap[$0] }
    return TalkScreen(
      home: pageHome, pinned: Set(project?.pinned ?? []), focusRequest: focus[pageHome, default: 0],
      attach: attach, opened: opened, failed: failed, visit: visits.visit(for: pageHome),
      columnPreferred: $columnPreferred
    )
    .environment(\.projectName, project?.name)
    .environment(\.projectsByID, projectsMap)
    .environment(\.nextUpDeck, shown ? deck : nil)
    .allowsHitTesting(shown)
    .accessibilityHidden(!shown)
  }

  /// A new project's page, in front or sliding out.
  @ViewBuilder private var newProjectPage: some View {
    if let shown = draft ?? parting {
      NewProjectPage(
        draft: Binding(get: { draft ?? shown }, set: { if draft != nil { draft = $0 } }), sent: launching != nil,
        attach: attach, send: launch, sealFrame: { sealFrame = $0 }
      )
      .padding(.top, Size.projectBarRoom)
      .padding(.horizontal, Spacing.m)
      .overlay(alignment: .topTrailing) {
        CornerButtons(layout: chatLayout, panelsShown: $columnPreferred)
      }
      .onExitCommand { if launching == nil { leaveDraft() } }
      .allowsHitTesting(draft != nil)
      .transition(.opacity)
    }
  }

  /// The home whose page is in front; `nil` while a new project's page covers them.
  private var shownHome: Home? { draft == nil ? home : nil }

  private var newSeal: NewSeal? {
    guard draft != nil else { return nil }
    return NewSeal(sent: launching != nil, landed: launching?.landed ?? false, symbol: launching?.symbol)
  }

  private var keptProjects: [Project.ID] {
    KeptPages.projects(made: madeProjects, open: project, alive: bar == nil ? nil : Set(projectsMap.keys))
  }

  /// A new project opens once its seal has landed and it is in the bar; a project gone elsewhere leaves the
  /// chat open; what the open project says new is seen.
  private func settle() {
    guard let value = bar?.value else { return }
    if let launching, launching.landed, let id = launching.project, value.projects.contains(where: { $0.id == id }) {
      if let symbol = launching.symbol { suggested[id] = symbol }
      turn(to: .project(id))
      handed = id
      self.launching = nil
      draft = nil
      project = id
    }
    if let project, !(value.projects + value.archived).contains(where: { $0.id == project }) { self.project = nil }
    if let project, value.unseen.contains(project) { send(SeeProject(project)) }
  }

  private var actions: ProjectBarActions {
    ProjectBarActions(
      open: { open($0) },
      start: {
        timing?.left()
        handed = nil
        parting = nil
        draft = NewProjectDraft()
      },
      rename: { id, name in send(RenameProject(id, to: name)) },
      reicon: { id, icon in send(SetProjectIcon(id, icon: icon)) },
      pin: { id, panel, pinned in send(PinPanel(panel, of: id, pinned: pinned)) },
      remember: { id, remembered in send(SetProjectRemembered(id, remembered: remembered)) },
      archive: { id in
        if project == id { project = nil }
        send(ArchiveProject(id, archived: true))
        notice = .archived(id)
      },
      delete: { id in
        if project == id { project = nil }
        send(DeleteProject(id))
        notice = .deleted()
      })
  }

  /// Turns are timed on this Mac only; another Mac's would include the network.
  private var timing: HomeSwitch? { machineChoice?.link == nil ? homeSwitch : nil }

  /// Opens `chosen`, its page already `made` when a swipe brought it into view.
  private func open(_ chosen: Home, made: Bool = false) {
    turn(to: chosen, made: made)
    leaveDraft()
    if case .project(let id) = chosen, shownBar.archived.contains(where: { $0.id == id }) {
      send(ArchiveProject(id, archived: false))
    }
    project = chosen.project
    if let id = chosen.project { send(SeeProject(id)) }
  }

  /// Times the turn when the page will change: to another home, or to the one a new project's field covers.
  private func turn(to chosen: Home, made: Bool = false) {
    guard chosen != home || draft != nil else { return }
    focusedCard = nil
    timing?.turned(to: chosen, kept: made || (chosen.project.map(madeProjects.contains) ?? true))
  }

  /// Sends a new project's words: its seal flies into the bar while the project is made.
  private func launch() {
    guard let draft, launching == nil else { return }
    launching = Launching(symbol: draft.symbol, from: sealFrame, landed: reduceMotion)
    Task {
      do throws(HostError) {
        launching?.project = try await host.run(StartProject(draft.words, icon: draft.chosenIcon)).id
        settle()
      } catch {
        launching = nil
        failed(error)
      }
    }
  }

  /// Puts a new project's page away; words already sent go on making their project.
  private func leaveDraft() {
    if draft != nil { parting = draft }
    draft = nil
    launching = nil
  }

  private func words(of notice: Notice) -> LocalizedStringResource {
    switch notice {
    case .archived: .loci("projects.archived")
    case .deleted: .loci("projects.deleted")
    case .card(_, let later, _): later ? .loci("deck.putOff") : .loci("deck.declined")
    }
  }

  private func undo(_ notice: Notice) {
    self.notice = nil
    switch notice {
    case .archived(let id, _): send(ArchiveProject(id, archived: false))
    case .deleted: send(RestoreDeletedProject())
    case .card(let card, _, _): send(SetNextUp(card.id, .restore, version: card.version))
    }
  }

  private var projectsMap: [Project.ID: Project] {
    Dictionary((shownBar.projects + shownBar.archived).map { ($0.id, $0) }) { first, _ in first }
  }

  private func openNotifiedCard() {
    guard let route = cardDelivery?.waiting, let bar = bar?.value else { return }
    leaveDraft()
    let projects = bar.projects + bar.archived
    let exists = route.home.project.map { id in projects.contains { $0.id == id } } ?? true
    if exists {
      turn(to: route.home)
      project = route.home.project
      focusedCard = route.card
    }
    cardDelivery?.waiting = nil
  }

  private var deck: NextUpDeckState {
    let cards = nextUps?.value ?? []
    let target = cards.first { $0.id == focusedCard }
    let shown = target.map { [$0] + cards.filter { $0.id != focusedCard } } ?? cards
    return NextUpDeckState(
      cards: shown, projects: projectsMap, flying: flight?.id, focused: target?.id,
      actions: NextUpActions(
        start: { card in
          if reduceMotion { land(card) } else { flight = card }
        },
        set: { card, choice in
          Task {
            do throws(HostError) {
              let after = try await host.run(SetNextUp(card.id, choice, version: card.version))
              switch choice {
              case .decline: notice = .card(after, later: false)
              case .later: notice = .card(after, later: true)
              case .keep, .restore: break
              }
            } catch {
              failed(error)
            }
          }
        },
        approve: { card, step in send(ApproveNextUp(card.id, version: card.version, step)) },
        undo: { card, made in send(UndoApproval(card.id, version: card.version, made: made.identifier)) }))
  }

  private func project(of card: NextUp) -> Project? {
    card.home.project.flatMap { id in (shownBar.projects + shownBar.archived).first { $0.id == id } }
  }

  /// The card is in its seal: the seal takes it, its home opens, and its question is said there.
  private func land(_ card: NextUp) {
    flight = nil
    turn(to: card.home)
    if !reduceMotion { stamps[card.home, default: 0] += 1 }
    leaveDraft()
    project = card.home.project
    if let id = card.home.project { send(SeeProject(id)) }
    send(StartNextUp(card.id, version: card.version))
  }

  private func send<C: Command>(_ command: C) {
    Task {
      do throws(HostError) {
        _ = try await host.run(command)
      } catch {
        failed(error)
      }
    }
  }
}
