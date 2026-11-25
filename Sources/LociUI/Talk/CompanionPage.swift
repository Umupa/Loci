import LociModel
import SwiftUI

/// The companion's page: the project bar over the chat or the project it has open, or over the field a new
/// project starts from. The open one is remembered for the Mac. A next-up card started from the deck flies into
/// its seal, and its project opens.
struct CompanionPage: View {
  @Environment(\.host) private var host
  @Environment(\.reducesMotion) private var reduceMotion
  let focusRequest: Int
  let attach: () -> Void
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @Binding var columnPreferred: Bool
  let memory: WindowMemory
  @State private var project: Project.ID?
  @State private var recalled = false
  @State private var bar: Feed<ProjectBar>?
  @State private var starting: Starting?
  @State private var notice: Notice?
  @State private var nextUps: Feed<[NextUp]>?
  @State private var flight: NextUp?
  /// How many cards each seal caught, to stamp it once more.
  @State private var stamps: [Home: Int] = [:]

  /// A project being started: the words, once sent, and the project they started.
  struct Starting: Equatable {
    var sent: String?
    var project: Project.ID?
  }

  /// What the last archiving, deletion, or card put off or declined took away, to undo.
  enum Notice: Equatable {
    case archived(Project.ID, serial: UUID = UUID())
    case deleted(serial: UUID = UUID())
    case card(EntityID, later: Bool, serial: UUID = UUID())
  }

  private var home: Home { project.map(Home.project) ?? .chat }
  private var shownBar: ProjectBar { bar?.value ?? ProjectBar(projects: []) }

  var body: some View {
    ZStack(alignment: .top) {
      Group {
        if let starting {
          NewProjectStage(sent: starting.sent, send: start)
            .padding(.top, Size.projectBarRoom)
            .padding(.horizontal, Spacing.m)
        } else {
          TalkScreen(
            home: home, pinned: Set(openProject?.pinned ?? []), focusRequest: focusRequest, attach: attach,
            opened: opened, failed: failed, columnPreferred: $columnPreferred
          )
          .id(home)
          .transition(.opacity)
          .environment(\.projectName, openProject?.name)
          .environment(\.nextUpDeck, deck)
        }
      }
      ProjectBarView(bar: shownBar, home: home, starting: starting != nil, stamps: stamps, actions: actions)
        .padding(.top, 11)
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
    .subscribing(WatchProjects(), into: $bar)
    .subscribing(WatchNextUps(of: home), into: $nextUps)
    .onChange(of: home) { nextUps = nil }
    .onAppear {
      guard !recalled else { return }
      recalled = true
      project = memory.recallProject()
    }
    .onChange(of: project) { memory.rememberProject(project) }
    .onChange(of: bar?.value) { settle() }
    .task(id: notice) {
      guard let shown = notice else { return }
      try? await Task.sleep(for: .seconds(6))
      if !Task.isCancelled, notice == shown { notice = nil }
    }
  }

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
        starting = nil
        if case .project(let id) = chosen, shownBar.archived.contains(where: { $0.id == id }) {
          send(ArchiveProject(id, archived: false))
        }
        withAnimation(reduceMotion ? nil : Motion.standard) { project = chosen.project }
        if let id = chosen.project { send(SeeProject(id)) }
      },
      start: { starting = Starting() },
      rename: { id, name in send(RenameProject(id, to: name)) },
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

  private func start(_ words: String) {
    starting?.sent = words
    Task {
      do throws(HostError) {
        starting?.project = try await host.run(StartProject(words)).id
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
    case .card(let id, _, _): send(SetNextUp(id, .restore))
    }
  }

  private var deck: NextUpDeckState {
    let projects = Dictionary((shownBar.projects + shownBar.archived).map { ($0.id, $0) }) { first, _ in first }
    return NextUpDeckState(
      cards: nextUps?.value ?? [], projects: projects, flying: flight?.id,
      actions: NextUpActions(
        start: { card in
          if reduceMotion { land(card) } else { flight = card }
        },
        set: { card, choice in
          send(SetNextUp(card.id, choice))
          switch choice {
          case .decline: notice = .card(card.id, later: false)
          case .later: notice = .card(card.id, later: true)
          case .keep, .restore: break
          }
        },
        approve: { card in send(ApproveNextUp(card.id)) },
        undo: { card in send(UndoApproval(card.id)) }))
  }

  private func project(of card: NextUp) -> Project? {
    card.home.project.flatMap { id in (shownBar.projects + shownBar.archived).first { $0.id == id } }
  }

  /// The card is in its seal: the seal takes it, its home opens, and its question is said there.
  private func land(_ card: NextUp) {
    flight = nil
    if !reduceMotion { stamps[card.home, default: 0] += 1 }
    starting = nil
    withAnimation(reduceMotion ? nil : Motion.standard) { project = card.home.project }
    if let id = card.home.project { send(SeeProject(id)) }
    send(StartNextUp(card.id))
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
