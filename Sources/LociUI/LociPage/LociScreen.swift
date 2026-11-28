import LociModel
import SwiftUI

/// The tabs of the companion's home page: its own, then its settings.
enum LociTab: String, CaseIterable, Hashable {
  case soul, memory, watch, diary, models, timers, connectors, usage

  static let groups: [[LociTab]] = [[.soul, .memory, .watch, .diary], [.models, .timers, .connectors, .usage]]

  /// Where the tab last looked at is kept.
  static let key = "companionTab"

  /// The tab a page opened at one shows, or else the one last looked at, or Soul.
  static func opening(asked: LociTab?, remembered: String) -> LociTab {
    asked ?? LociTab(rawValue: remembered) ?? .soul
  }

  var title: LocalizedStringResource {
    switch self {
    case .soul: .loci("loci.soul")
    case .memory: .loci("loci.memory")
    case .watch: .loci("loci.watch")
    case .diary: .loci("loci.diary")
    case .models: .loci("loci.models")
    case .timers: .loci("loci.timers")
    case .connectors: .loci("connectors.tab")
    case .usage: .loci("usage.tab")
    }
  }
}

/// The companion's home page: back to the chat in the corner, its face, name and how it is, what you have done
/// together, a button to message it, and its tabs, which stay at the top as the page scrolls.
struct LociScreen: View {
  /// Where the page opens: at a tab, or the one last looked at, and what inside it is open.
  struct Opening: Hashable {
    /// `nil` opens the tab last looked at.
    var tab: LociTab?
    /// Starts that schedule open on the Timers page.
    var opened: ScheduleRef?
    /// Lights that connector's row.
    var connector: ConnectorID?
    /// Starts that page of the wiki open on the Memory page.
    var wikiPage: String?
    /// Starts that home's watch open on the Watch page.
    var watch: Home?
  }

  @State private var page: Feed<LociPage>?
  @Environment(\.sidebarShown) private var sidebarShown
  @Environment(\.companionFlight) private var flight
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.pagesOver) private var pagesOver
  @AppStorage(LociTab.key) private var rememberedTab = ""
  @State private var chosen: LociTab?
  @State private var stuck = false
  @State private var risen = false
  private let opening: Opening
  private let back: (() -> Void)?
  private let message: (() -> Void)?

  /// `back` returns to the chat and `message` puts the keyboard in its field; without them the page has neither.
  init(_ opening: Opening = Opening(), back: (() -> Void)? = nil, message: (() -> Void)? = nil) {
    self.opening = opening
    self.back = back
    self.message = message
  }

  init(tab: LociTab? = nil, opened: ScheduleRef? = nil, connector: ConnectorID? = nil, wikiPage: String? = nil) {
    self.init(Opening(tab: tab, opened: opened, connector: connector, wikiPage: wikiPage))
  }

  private var tab: LociTab { chosen ?? LociTab.opening(asked: opening.tab, remembered: rememberedTab) }

  private var tabSelection: Binding<LociTab> {
    Binding(
      get: { tab },
      set: {
        chosen = $0
        rememberedTab = $0.rawValue
      })
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        HomeHeader(page: page?.value, message: message, rise: rise)
          .padding(.horizontal, Self.margin)
          .padding(.top, Spacing.l)
          .padding(.bottom, Spacing.l)
        Section {
          content
            .padding(.horizontal, Self.margin)
            .padding(.top, 26)
            .padding(.bottom, 56)
            .rising(4, risen: risen, when: rise)
        } header: {
          VStack(spacing: 0) {
            UnderlineTabs(selection: tabSelection).padding(.horizontal, Self.margin)
            Rectangle().fill(Palette.line).frame(height: Size.hairline)
          }
          .background(Palette.canvas)
          .rising(3, risen: risen, when: rise)
        }
      }
    }
    .scrollIndicators(.never)
    .onScrollGeometryChange(for: Bool.self) {
      $0.contentOffset.y + $0.contentInsets.top > Self.stickAt
    } action: { _, past in
      stuck = past
    }
    .safeAreaInset(edge: .top, spacing: 0) { topRow }
    .background(Palette.canvas)
    .subscribing(LociHome(), into: $page)
    .onAppear { risen = true }
  }

  /// The parts under the face rise in one after another only as the face flies in from the chat.
  private var rise: Bool { flight != nil && !reduceMotion }

  @ViewBuilder private var content: some View {
    if let page = page?.value {
      Group {
        switch tab {
        case .soul: SoulTab(soul: page.soul)
        case .models: ModelsTab()
        case .memory:
          MemoryTab(memory: page.memory, profile: page.profile, today: page.today, opened: opening.wikiPage)
        case .watch: WatchTab(chosen: opening.watch ?? .chat)
        case .diary: DiaryTab(diaries: page.diaries)
        case .timers: TimersTab(opened: opening.opened)
        case .connectors: ConnectorsTab(focused: opening.connector)
        case .usage: UsageTab()
        }
      }
      .id(tab)
      .arriving()
      .animatingArrivals(tab)
    }
  }

  /// Back to the chat, and the companion's face and name once the header has scrolled away.
  private var topRow: some View {
    HStack(spacing: Spacing.s) {
      if let back {
        Button(action: back) {
          HStack(spacing: Spacing.xxs) {
            Image(systemName: Symbols.back).font(.system(size: 12, weight: .medium))
            Text(.loci("projects.chat")).font(.system(size: 13))
          }
          .foregroundStyle(Palette.inkMuted)
          .padding(.vertical, Spacing.xxs)
          .padding(.horizontal, Spacing.xs)
          .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .keyboardShortcut(pagesOver ? nil : KeyboardShortcut("[", modifiers: .command))
        .help(Text(.loci("companion.backToChat")))
        .rising(0, risen: risen, when: rise)
      }
      CompanionMini()
        .opacity(stuck ? 1 : 0)
        .offset(y: stuck || reduceMotion ? 0 : 4)
        .animation(reduceMotion ? nil : Motion.quick, value: stuck)
        .accessibilityHidden(!stuck)
      Spacer(minLength: 0)
    }
    .frame(height: Self.topRow)
    .padding(.leading, CompanionBadge.leading(sidebarShown: sidebarShown) - Spacing.xs)
    .padding(.top, Spacing.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.canvas)
  }

  /// From the page's edge to its words.
  static let margin: CGFloat = 48
  private static let topRow: CGFloat = 38
  /// How far the page scrolls before the header is gone under the tabs.
  private static let stickAt: CGFloat = 130
}

/// The companion's small face and name, at the top of its page once the header has scrolled away.
private struct CompanionMini: View {
  @Environment(\.companionName) private var name

  var body: some View {
    HStack(spacing: Spacing.xs) {
      LociAvatar(size: 22)
      (name.isEmpty ? Text(.loci("companion.title")) : Text(verbatim: name))
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundStyle(Palette.ink)
        .lineLimit(1)
    }
  }
}

extension View {
  /// Comes up into place after the face, `step` places along, as the home page opens from the chat.
  func rising(_ step: Int, risen: Bool, when rises: Bool) -> some View {
    opacity(rises && !risen ? 0 : 1)
      .offset(y: rises && !risen ? 10 : 0)
      .animation(rises ? Motion.companionRise.delay(0.14 + Double(step) * 0.045) : nil, value: risen)
  }
}

extension Day {
  /// `11-17`, as the page lists days.
  var short: String {
    String(format: "%02d-%02d", month, day)
  }
}
