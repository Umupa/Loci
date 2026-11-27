import LociModel
import SwiftUI

/// The companion's page: the project bar over the chat or the project it has open, or over the field a new
/// project starts from. The open one is remembered for the Mac. A next-up card started from the deck flies into
/// its seal, and its project opens.
struct CompanionPage: View {
  @Environment(\.host) private var host
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.sidebarShown) private var sidebarShown
  @Environment(\.machineChoice) private var machineChoice
  let focusRequest: Int
  let attach: () -> Void
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @Binding var columnPreferred: Bool
  let memory: WindowMemory
  let visits: ConversationVisits
  /// Opens on a new project's field, for a snapshot.
  var opening: Starting?
  @State private var project: Project.ID?
  @State private var recalled = false
  @State private var bar: Feed<ProjectBar>?
  @State private var starting: Starting?
  @State private var notice: Notice?
  @State private var nextUps: Feed<[NextUp]>?
  @State private var flight: NextUp?
  /// How many cards each seal caught, to stamp it once more.
  @State private var stamps: [Home: Int] = [:]
  /// Asks the chat's input field for the keyboard; only while the chat shows, since it stays made under a
  /// project.
  @State private var chatFocus = 0
  @State private var pageWidth: CGFloat = 0
  @State private var homeSwitch = HomeSwitch.logged()
  /// The chat's layout, for the layout button over a new project's field.
  @AppStorage(TalkLayout.key) private var storedLayout = Data()

  /// A project being started: the words, once sent, and the project they started.
  struct Starting: Equatable {
    var sent: String?
    var project: Project.ID?
  }

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
      talk(.chat, shown: chatShown, focusRequest: chatFocus)
      if let starting {
        NewProjectStage(sent: starting.sent, send: start)
          .padding(.top, Size.projectBarRoom)
          .padding(.horizontal, Spacing.m)
          .overlay(alignment: .topTrailing) {
            CornerButtons(layout: chatLayout, panelsShown: $columnPreferred)
          }
      } else if let project {
        talk(.project(project), shown: true, focusRequest: focusRequest)
          .id(project)
      }
      let leadingClearance = sidebarShown ? Spacing.m : Size.projectBarClearance
      let barBudget =
        pageWidth > 0 ? max(240, pageWidth - leadingClearance - Size.projectBarClearance) : Size.projectBarWidest
      BarClearance(leading: leadingClearance, trailing: Size.projectBarClearance) {
        ProjectBarView(
          bar: shownBar, home: home, maxWidth: barBudget, starting: starting != nil,
          startingSent: starting?.sent != nil, stamps: stamps, actions: actions)
      }
      .padding(.top, 11)
    }
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
    .animation(reduceMotion ? nil : Motion.standard, value: starting == nil)
    .showingDocuments(coversPanels: true)
    .subscribing(WatchProjects(), into: $bar)
    .subscribing(WatchNextUps(of: home), into: $nextUps)
    .onChange(of: home) {
      nextUps = nil
      timing?.shown(home)
    }
    .onDisappear { timing?.left() }
    .environment(\.homeSwitch, timing)
    .onChange(of: chatShown) { if chatShown { chatFocus += 1 } }
    .onChange(of: focusRequest) { if chatShown { chatFocus += 1 } }
    .onAppear {
      guard !recalled else { return }
      recalled = true
      project = memory.recallProject()
      if let opening { starting = opening }
    }
    .onChange(of: project) { memory.rememberProject(project) }
    .onChange(of: bar?.value) { settle() }
    .task(id: notice) {
      guard let shown = notice else { return }
      try? await Task.sleep(for: .seconds(6))
      if !Task.isCancelled, notice == shown { notice = nil }
    }
  }

  /// A home's conversation and panels. The chat's stays made while a project is open over it, so going back to
  /// it shows it as it was instead of making it again.
  private func talk(_ shownHome: Home, shown: Bool, focusRequest: Int) -> some View {
    TalkScreen(
      home: shownHome, pinned: Set(shownHome == home ? openProject?.pinned ?? [] : []), focusRequest: focusRequest,
      attach: attach, opened: opened, failed: failed, visit: visits.visit(for: shownHome),
      columnPreferred: $columnPreferred
    )
    .environment(\.projectName, shownHome == home ? openProject?.name : nil)
    .environment(\.projectsByID, projectsMap)
    .environment(\.nextUpDeck, deck)
    .opacity(shown ? 1 : 0)
    .allowsHitTesting(shown)
    .accessibilityHidden(!shown)
  }

  private var chatShown: Bool { starting == nil && project == nil }

  private var openProject: Project? {
    guard let project else { return nil }
    return (shownBar.projects + shownBar.archived).first { $0.id == project }
  }

  /// A started project is done once it has its name; a project gone elsewhere leaves the chat open; what the
  /// open project says new is seen.
  private func settle() {
    guard let value = bar?.value else { return }
    if let id = starting?.project, value.projects.contains(where: { $0.id == id }) {
      starting = nil
      project = id
    }
    if let project, !(value.projects + value.archived).contains(where: { $0.id == project }) { self.project = nil }
    if let project, value.unseen.contains(project) { send(SeeProject(project)) }
  }

  private var actions: ProjectBarActions {
    ProjectBarActions(
      open: { chosen in
        turn(to: chosen)
        starting = nil
        if case .project(let id) = chosen, shownBar.archived.contains(where: { $0.id == id }) {
          send(ArchiveProject(id, archived: false))
        }
        project = chosen.project
        if let id = chosen.project { send(SeeProject(id)) }
      },
      start: {
        timing?.left()
        starting = Starting()
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

  /// Times the turn when the page will change: to another home, or to the one a new project's field covers.
  private func turn(to chosen: Home) {
    guard chosen != home || starting != nil else { return }
    timing?.turned(to: chosen, kept: chosen == .chat)
  }

  private func start(_ words: String, icon: String?) {
    starting?.sent = words
    Task {
      do throws(HostError) {
        starting?.project = try await host.run(StartProject(words, icon: icon)).id
        settle()
      } catch {
        starting = nil
        failed(error)
      }
    }
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

  private var deck: NextUpDeckState {
    NextUpDeckState(
      cards: nextUps?.value ?? [], projects: projectsMap, flying: flight?.id,
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
    starting = nil
    withAnimation(reduceMotion ? nil : Motion.standard) { project = card.home.project }
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
