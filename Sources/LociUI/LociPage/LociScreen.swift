import LociModel
import SwiftUI

/// The pages of Loci's own page.
enum LociTab: Hashable {
  case soul, memory, diary, timers, connectors
}

/// Loci's own page: its face, which the person can change, its name, what they have done together, and its
/// Soul, memory and diary.
struct LociScreen: View {
  @State private var page: Feed<LociPage>?
  @Environment(\.host) private var host
  @Environment(\.showFailure) private var showFailure
  @Environment(\.companionName) private var name
  @State private var renaming = false
  @State private var draft = ""
  @State private var tab: LociTab
  private let opened: ScheduleRef?
  private let connector: ConnectorID?
  private let wikiPage: String?

  /// `opened` starts that schedule open on the Timers page; `connector` lights that connector's row; `wikiPage`
  /// starts that page of the wiki open on the Memory page.
  init(tab: LociTab = .soul, opened: ScheduleRef? = nil, connector: ConnectorID? = nil, wikiPage: String? = nil) {
    _tab = State(initialValue: tab)
    self.opened = opened
    self.connector = connector
    self.wikiPage = wikiPage
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        hero
        CapsulePicker(
          selection: $tab,
          options: [
            (.soul, .loci("loci.soul")), (.memory, .loci("loci.memory")), (.diary, .loci("loci.diary")),
            (.timers, .loci("loci.timers")), (.connectors, .loci("connectors.tab")),
          ]
        )
        .padding(.top, 34)
        .padding(.bottom, 22)
        if let page = page?.value {
          Group {
            switch tab {
            case .soul: SoulTab(soul: page.soul)
            case .memory: MemoryTab(memory: page.memory, profile: page.profile, today: page.today, opened: wikiPage)
            case .diary: DiaryTab(diaries: page.diaries)
            case .timers: TimersTab(opened: opened)
            case .connectors: ConnectorsTab(focused: connector)
            }
          }
          .id(tab)
          .arriving()
        }
      }
      .animatingArrivals(tab)
      .padding(.top, 44)
      .padding(.horizontal, 64)
      .padding(.bottom, 56)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollIndicators(.never)
    .background(Palette.canvas)
    .subscribing(LociHome(), into: $page)
    .alert(Text(.loci("companion.name")), isPresented: $renaming) {
      TextField(text: $draft) { Text(.loci("companion.name")) }
      Button(.loci("dialog.cancel"), role: .cancel) {}
      Button(.loci("loci.save")) { rename(draft) }
    }
  }

  private func rename(_ name: String) {
    Task {
      do throws(HostError) {
        _ = try await host.run(RenameCompanion(name))
      } catch {
        showFailure(error)
      }
    }
  }

  private var hero: some View {
    HStack(spacing: Spacing.xl) {
      Portrait()
      VStack(alignment: .leading, spacing: Spacing.s) {
        Button {
          draft = name
          renaming = true
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            (name.isEmpty ? Text(.loci("companion.title")) : Text(verbatim: name))
              .font(.system(size: 46, weight: .semibold, design: .serif))
              .lineLimit(1)
            Image(systemName: Symbols.pencil).font(.system(size: 15)).foregroundStyle(Palette.inkMuted)
          }
        }
        .buttonStyle(.plain)
        .help(Text(.loci("companion.name")))
        .changesData()
        if let feeling = page?.value?.feeling {
          FeelingLine(feeling: feeling).padding(.bottom, Spacing.xxs)
        }
        if let together = page?.value?.together {
          FlowRow(spacing: Spacing.xs) {
            FactPill(count: together.days, unit: .loci("loci.days"))
            FactPill(count: together.messages, unit: .loci("loci.messages"))
            FactPill(count: together.itemsReadTogether, unit: .loci("loci.readTogether"))
          }
        }
      }
    }
  }
}

/// A count and what it counts, in a quiet capsule.
private struct FactPill: View {
  let count: Int
  let unit: LocalizedStringResource

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      Text(count, format: .number).font(.system(size: 12.5, weight: .medium).monospaced()).foregroundStyle(Palette.ink)
      Text(unit).font(.system(size: 12.5)).foregroundStyle(Palette.inkMuted)
    }
    .padding(.vertical, Spacing.xxs)
    .padding(.horizontal, 10)
    .background(Palette.fill, in: Capsule())
    .fixedSize()
  }
}

extension Day {
  /// `11-17`, as the page lists days.
  var short: String {
    String(format: "%02d-%02d", month, day)
  }
}
