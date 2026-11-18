import LociModel
import SwiftUI

/// The pages of Loci's own page.
enum LociTab: Hashable {
  case soul, memory, diary
}

/// Loci's own page: its face, which the person can change, its name, what they have done together, and its
/// Soul, memory and diary.
struct LociScreen: View {
  @State private var page: Feed<LociPage>?
  @State private var tab: LociTab

  init(tab: LociTab = .soul) {
    _tab = State(initialValue: tab)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        hero
        CapsulePicker(
          selection: $tab,
          options: [(.soul, .loci("loci.soul")), (.memory, .loci("loci.memory")), (.diary, .loci("loci.diary"))]
        )
        .padding(.top, 34)
        .padding(.bottom, 22)
        if let page = page?.value {
          Group {
            switch tab {
            case .soul: SoulTab(soul: page.soul)
            case .memory: MemoryTab(memory: page.memory, profile: page.profile, today: page.today)
            case .diary: DiaryTab(diaries: page.diaries)
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
  }

  private var hero: some View {
    HStack(spacing: Spacing.xl) {
      Portrait()
      VStack(alignment: .leading, spacing: Spacing.s) {
        Text(verbatim: "Loci").font(.system(size: 46, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
        if let together = page?.value?.together {
          HStack(spacing: Spacing.xs) {
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
  }
}

extension Day {
  /// `11-17`, as the page lists days.
  var short: String {
    String(format: "%02d-%02d", month, day)
  }
}
