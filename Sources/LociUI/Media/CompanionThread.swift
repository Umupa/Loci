import LociModel
import SwiftUI

/// The conversation on an item: a mentor chosen at the top to read along, and every question asked here,
/// each answer marked with the mentor who gave it. Changing mentors keeps what was said before.
struct CompanionThread: View {
  @Environment(\.host) private var host
  @Environment(\.locale) private var locale
  let item: EntityID
  let conversation: ItemConversation?
  let mentors: [Mentor]
  @Binding var draft: PassageDraft?
  let revealPassage: @MainActor (Locator) -> Void

  var body: some View {
    if let companion {
      ConversationView(
        mentor: companion, conversation: thread, draft: $draft, revealPassage: revealPassage,
        send: { (text: String, passage: Passage?) async throws(HostError) -> Done in
          try await host.run(AskCompanion(item: item, mentor: companion.id, text: text, passage: passage))
        },
        stop: { _ = try? await host.run(StopCompanion(item: item)) },
        startOver: { () async throws(HostError) -> Done in try await host.run(StartOverCompanion(item: item)) },
        answeredBy: { message in answerer[message.id] }, showsDays: true, plainComposer: true
      )
      .safeAreaInset(edge: .top, spacing: 0) {
        CompanionPicker(companion: companion, mentors: mentors) { chosen in
          Task { _ = try? await host.run(ChooseCompanion(item: item, mentor: chosen.id)) }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  /// The mentor reading along: the one chosen here, or the first there is.
  private var companion: Mentor? {
    mentors.first { $0.id == conversation?.companion } ?? mentors.first
  }

  /// The item's messages as one conversation, the turn running now at its end.
  private var thread: Conversation? {
    guard let conversation, let companion else { return nil }
    return Conversation(
      mentor: companion.id, messages: conversation.messages.map(\.message), turn: conversation.turn?.turn,
      context: conversation.context)
  }

  /// Who said each message, including the turn running now.
  private var answerer: [EntityID: Mentor] {
    guard let conversation else { return [:] }
    let byID = Dictionary(mentors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var who: [EntityID: Mentor] = [:]
    for said in conversation.messages { who[said.message.id] = byID[said.mentor] ?? departed(said.mentor) }
    if let turn = conversation.turn {
      for message in turn.turn.messages { who[message.id] = byID[turn.mentor] ?? departed(turn.mentor) }
    }
    return who
  }

  private var departedName: String {
    var resource = LocalizedStringResource.loci("companion.departed")
    resource.locale = locale
    return String(localized: resource)
  }

  /// A mentor deleted since it answered, named as such.
  private func departed(_ id: EntityID) -> Mentor? {
    try? Mentor(
      id: id, name: departedName, avatar: Mentor.Mark.allCases[0].rawValue,
      color: MentorColor(red: 0x8A, green: 0x86, blue: 0x80), provider: .pi)
  }
}

/// The capsule naming the mentor reading along; a menu of the others to change to.
struct CompanionPicker: View {
  let companion: Mentor
  let mentors: [Mentor]
  let choose: (Mentor) -> Void

  var body: some View {
    Menu {
      ForEach(mentors, id: \.id) { mentor in
        Button {
          choose(mentor)
        } label: {
          Text(verbatim: mentor.name)
        }
      }
    } label: {
      HStack(spacing: Spacing.xs) {
        Avatar(mentor: companion, size: Size.avatarSmall)
        Text(verbatim: companion.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
        Image(systemName: Symbols.popup)
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(Palette.onAccent)
          .frame(width: Spacing.m, height: Spacing.m)
          .background(RoundedRectangle(cornerRadius: 4).fill(Palette.accent))
      }
      .padding(.leading, 5)
      .padding(.trailing, 6)
      .frame(height: 30)
      .background(Capsule().fill(Palette.surface).shadow(color: .black.opacity(0.06), radius: 1, y: 1))
      .overlay(Capsule().strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityLabel(Text(.loci("companion.choose")))
  }
}
