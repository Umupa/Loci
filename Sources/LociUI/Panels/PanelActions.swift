import AppKit
import LociModel
import SwiftUI

/// What the panel column asks of the screen around it.
struct PanelActions {
  /// Opens a list line's link: a web page in the built-in browser, or a `loci://` place.
  let open: (URL) -> Void
  /// Opens an item read partway, where it was left.
  let openItem: (EntityID) -> Void
  /// Says something in the main conversation, as the person.
  let ask: (String) -> Void
  /// Puts the composer to asking for a new panel.
  let create: () -> Void
  /// Fills the composer to ask Loci to change a panel.
  let revise: (Panel) -> Void
  let refresh: (PanelRef) -> Void
  let moveToTop: (PanelSlot) -> Void
  /// Removes the panel and its file.
  let remove: (PanelRef) -> Void
  /// Makes the person's edit to a panel's items; `false` when the host refused it.
  let edit: @MainActor (EditPanel) async -> Bool
  /// Keeps the person's take on a list line; `false` when the host refused it.
  let mark: @MainActor (MarkPanelLine) async -> Bool
  /// Shows a project's panel in the chat's column too, or stops.
  let pin: (PanelRef, Bool) -> Void
}

/// What right-clicking a panel offers. 「接着读」 belongs to the app, so it can only be moved. A project's
/// panel can be pinned to the chat; pinned there, it is refreshed, moved and unpinned, and changed in its
/// project.
enum PanelMenu: Equatable {
  case refresh, revise, pin, unpin, moveToTop, remove

  static func entries(for slot: PanelSlot, in home: Home = .chat, pinned: Bool = false) -> [PanelMenu] {
    switch slot {
    case .reading: [.moveToTop]
    case .pinned: [.refresh, .moveToTop, .unpin]
    case .panel where home == .chat: [.refresh, .revise, .moveToTop, .remove]
    case .panel: [.refresh, .revise, pinned ? .unpin : .pin, .moveToTop, .remove]
    }
  }

  var name: LocalizedStringResource {
    switch self {
    case .refresh: .loci("panels.refresh")
    case .revise: .loci("panels.revise")
    case .pin: .loci("panels.pinToChat")
    case .unpin: .loci("panels.unpinFromChat")
    case .moveToTop: .loci("panels.moveToTop")
    case .remove: .loci("panels.remove")
    }
  }
}

extension EnvironmentValues {
  /// The home of the panels drawn here; a pinned panel's is its project.
  @Entry var panelHome: Home = .chat
  /// The panels of the project shown here that are pinned to the chat, by name.
  @Entry var pinnedPanels: Set<String> = []
  /// Whether the panel drawn here is a project's, pinned to the chat's column.
  @Entry var pinnedHere = false
  /// The project a pinned panel belongs to, when shown in the chat's column.
  @Entry var pinnedProject: Project?
  /// Known projects by id, so pinned panels and folded rails can show their seals.
  @Entry var projectsByID: [Project.ID: Project] = [:]
  /// Whether the sidebar is currently shown beside the page.
  @Entry var sidebarShown = true
}

/// A sentence with `**bold**` spans, split where the bold starts and ends. An unclosed `**` is kept as written.
struct BoldSpans {
  struct Span: Equatable {
    let text: String
    let bold: Bool
  }

  let spans: [Span]

  init(_ text: String) {
    var spans: [Span] = []
    var rest = Substring(text)
    while let open = rest.range(of: "**"), let close = rest[open.upperBound...].range(of: "**") {
      if open.lowerBound > rest.startIndex { spans.append(Span(text: String(rest[..<open.lowerBound]), bold: false)) }
      spans.append(Span(text: String(rest[open.upperBound..<close.lowerBound]), bold: true))
      rest = rest[close.upperBound...]
    }
    if !rest.isEmpty { spans.append(Span(text: String(rest), bold: false)) }
    self.spans = spans
  }
}

/// Words put into the composer from outside it; each new `serial` puts them in again.
struct ComposerFill: Equatable {
  let text: String
  let serial: Int

  /// 「改一下『标题』：」, for the person to finish.
  static func revising(_ panel: Panel, serial: Int, locale: Locale) -> ComposerFill {
    var words = LocalizedStringResource.loci("panels.reviseFill \(panel.title)")
    words.locale = locale
    return ComposerFill(text: String(localized: words), serial: serial)
  }
}

/// Asking Loci for a new panel from the column's foot: the composer asks what to follow, then the column holds
/// a skeleton until the panel is there or the turn that was making it ends.
enum NewPanel: Equatable {
  case asking
  /// The panels there were when the request was sent, whether its turn has started, and what marks the
  /// skeleton.
  case building(known: Set<String>, started: Bool, sources: PanelSources)

  /// What the request becomes once the column holds `names` and Loci is or is not `working`; `nil` when the
  /// skeleton should go.
  func settled(names: Set<String>, working: Bool) -> NewPanel? {
    guard case .building(let known, let started, let sources) = self else { return self }
    if !names.subtracting(known).isEmpty { return nil }
    if working { return .building(known: known, started: true, sources: sources) }
    return started ? nil : self
  }

  /// What is said to Loci, so it knows to make a panel of it.
  static func request(_ text: String, locale: Locale) -> String {
    NewPanelRequest.message(text, locale: locale)
  }
}

/// What the main conversation's composer does for the panel column beside it: ask for a new panel, take
/// words to change one, and say when Loci starts and stops working. Elsewhere it does none of these.
struct PanelRequest {
  var making: Binding<Bool> = .constant(false)
  var made: (String) -> Void = { _ in }
  var fill: ComposerFill?
  var working: (Bool) -> Void = { _ in }
}

extension PanelColumn {
  /// The names of Loci's panels in the column.
  var panelNames: Set<String> {
    Set(
      slots.compactMap {
        if case .panel(let panel) = $0 { panel.name } else { nil }
      })
  }
}

/// Which way a panel's pages turned, so the new page slides in from that side.
enum PageTurn: Equatable {
  case forward, back

  init(from: Int, to: Int) {
    self = to >= from ? .forward : .back
  }
}
