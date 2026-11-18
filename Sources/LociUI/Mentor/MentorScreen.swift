import LociModel
import SwiftUI

/// A mentor's page: who it is and what it runs on, what it is doing, its courses on a shelf, and its
/// memory and soul as it wrote them.
struct MentorScreen: View {
  @Environment(\.host) private var host
  let mentor: EntityID
  @State private var page: Feed<MentorPage>?
  @State private var conversation: Feed<Conversation>?
  @State private var mind: Feed<Mind>?
  @State private var tab = MindTab.memory
  @State private var soulFile: LocalFile?

  var body: some View {
    ScrollView {
      if let page = page?.value {
        VStack(spacing: 0) {
          MentorHero(mentor: page.mentor, turn: conversation?.value?.turn)
          Bookshelf(page: page, writingCatalog: conversation?.value?.turn != nil)
            .padding(.top, 40)
            .padding(.bottom, Spacing.xs)
          CapsulePicker(
            selection: $tab, options: [(.memory, .loci("mentor.memory")), (.soul, .loci("mentor.soul"))]
          )
          .padding(.top, 36)
          .padding(.bottom, 18)
          if let mind = mind?.value {
            switch tab {
            case .memory: MemoryList(files: mind.memory)
            case .soul: SoulSheet(soul: mind.soul, file: soulFile, color: page.mentor.tone)
            }
          }
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 40)
        .padding(.top, 46)
        .padding(.bottom, 70)
        .frame(maxWidth: .infinity)
      }
    }
    .background(Palette.canvas)
    .navigationTitle(Text(verbatim: page?.value?.mentor.name ?? ""))
    .subscribing(OneMentor(mentor: mentor), into: $page)
    .subscribing(MentorConversation(mentor: mentor), into: $conversation)
    .subscribing(MentorMind(mentor: mentor), into: $mind)
    .task(id: mentor) { soulFile = await host.localFile(.soul(mentor)) }
  }
}

enum MindTab: Hashable {
  case memory, soul
}

/// The portrait, name, agent and what the mentor is doing now.
struct MentorHero: View {
  let mentor: Mentor
  let turn: LiveTurn?

  var body: some View {
    VStack(spacing: 12) {
      Portrait(mentor: mentor)
      Text(verbatim: mentor.name)
        .font(Typography.mentorName)
        .foregroundStyle(Palette.ink)
        .multilineTextAlignment(.center)
        .padding(.top, 6)
      AgentChoiceMenu(mentor: mentor, parts: .all)
      if let turn { WorkingChip(turn: turn) }
    }
    .frame(maxWidth: .infinity)
    .background(alignment: .top) {
      EllipticalGradient(colors: [mentor.tone.color.opacity(0.22), mentor.tone.color.opacity(0)])
        .frame(width: 420, height: 260)
        .offset(y: -60)
        .allowsHitTesting(false)
    }
  }
}

/// The mentor's sign, large and glowing on the page.
struct Portrait: View {
  let mentor: Mentor
  var size: CGFloat = 84

  var body: some View {
    Avatar(mentor: mentor, size: size)
      .shadow(color: mentor.tone.color.opacity(0.4), radius: 15, y: 10)
      .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
  }
}

/// What the mentor is doing right now, in a capsule: the kind of work and what it works on.
struct WorkingChip: View {
  let turn: LiveTurn

  var body: some View {
    HStack(spacing: Spacing.xs) {
      TimelineView(.animation) { timeline in
        let beat = (sin(timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.4) + 1) / 2
        Circle().fill(Palette.accent).frame(width: 7, height: 7).scaleEffect(0.8 + 0.2 * beat)
      }
      Text(verb).font(.system(size: 12)).foregroundStyle(Palette.ink)
      if let subject {
        Text(verbatim: subject)
          .font(.system(size: 11.5).monospaced())
          .foregroundStyle(Palette.inkMuted)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .padding(.leading, 10)
    .padding(.trailing, 12)
    .frame(height: 26)
    .background(Capsule().fill(Palette.surface).shadow(color: .black.opacity(0.06), radius: 7, y: 4))
    .overlay(Capsule().strokeBorder(Palette.line, lineWidth: Size.hairline))
  }

  private var tool: ToolActivity? {
    turn.latestTool.flatMap { $0.state == .running ? $0 : nil }
  }

  private var verb: LocalizedStringResource {
    switch tool?.kind {
    case .read: .loci("activity.read")
    case .edit, .create, .delete: .loci("activity.edit")
    case .execute: .loci("activity.execute")
    case .search: .loci("activity.search")
    case .other, nil: .loci("activity.thinking")
    }
  }

  /// The path, the command or the query.
  private var subject: String? {
    tool?.subject
  }
}

extension MentorColor {
  /// The colour moved `amount` of the way to white, at `level` 1, or to black, at 0.
  func mixed(toward level: Double, _ amount: Double) -> Color {
    func channel(_ value: UInt8) -> Double { Double(value) / 255 + (level - Double(value) / 255) * amount }
    return Color(.sRGB, red: channel(red), green: channel(green), blue: channel(blue))
  }
}
