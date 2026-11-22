import LociModel
import SwiftUI

/// The panels beside the main conversation, top to bottom, with the skeleton of one being made and the button
/// that asks for a new one at the foot. The top fades under the button that folds the column away.
struct PanelColumnView: View {
  let column: PanelColumn
  /// What marks the skeleton of a panel being made, while one is.
  var building: PanelSources?
  /// The composer is asking for a new panel, so the button that started it steps back.
  var making = false
  let actions: PanelActions
  /// Panels that start opened out, and the page a paging panel starts on, by name, for a snapshot.
  var opened: Set<String> = []
  var pages: [String: Int] = [:]
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var position = ScrollPosition(edge: .top)

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        ForEach(column.slots, id: \.key) { slot in
          view(of: slot).transition(arrival)
        }
        if let building { PanelSkeleton(sources: building).transition(arrival) }
        NewPanelButton(action: actions.create).opacity(making ? 0.35 : 1).disabled(making || building != nil)
          .changesData()
      }
      .padding(.top, 70)
      .padding(.horizontal, Spacing.m)
      .padding(.bottom, 40)
      .animation(reduceMotion ? nil : Motion.standard, value: column.slots.map(\.key))
      .animation(reduceMotion ? nil : Motion.standard, value: building != nil)
      .animation(reduceMotion ? nil : Motion.quick, value: making)
    }
    .scrollPosition($position)
    .scrollIndicators(.never)
    .mask {
      VStack(spacing: 0) {
        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 72)
        Color.black
      }
    }
    .onChange(of: building != nil, initial: true) {
      if building != nil { withAnimation(reduceMotion ? nil : Motion.standard) { position.scrollTo(edge: .bottom) } }
    }
  }

  /// A panel just made rises into place.
  private var arrival: AnyTransition {
    reduceMotion ? .identity : .opacity.combined(with: .offset(y: Spacing.m)).combined(with: .scale(scale: 0.97))
  }

  @ViewBuilder private func view(of slot: PanelSlot) -> some View {
    switch slot {
    case .reading(let readings):
      if !readings.isEmpty { ReadingPanel(readings: readings, actions: actions) }
    case .panel(let panel):
      PanelCard(
        panel: panel, refreshing: column.refreshing.contains(panel.name), actions: actions,
        open: opened.contains(panel.name), page: pages[panel.name] ?? 0)
    }
  }
}

extension PanelSlot {
  /// Keeps a slot's place as the column changes: 「接着读」 has one, and each panel its name.
  var key: String {
    switch self {
    case .reading: "/reading"
    case .panel(let panel): panel.name
    }
  }
}

private struct NewPanelButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: Spacing.xs) {
        Image(systemName: Symbols.add).font(.system(size: 13, weight: .medium))
        Text(.loci("panels.new")).font(.system(size: 14))
      }
      .foregroundStyle(Palette.ink.opacity(0.85))
      .frame(maxWidth: .infinity, minHeight: Size.composerHeight)
      .background(Palette.surface, in: .capsule)
      .overlay(Capsule().strokeBorder(Palette.bubbleEdge, lineWidth: Size.hairline))
      .contentShape(.capsule)
    }
    .buttonStyle(PressStyle(scale: 0.98))
  }
}
