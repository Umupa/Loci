import LociModel
import SwiftUI

/// The sidebar draws its own selection: an amber wash, the same whether or not the sidebar has keyboard
/// focus. The system's list selection follows the system accent color and turns gray when focus is
/// elsewhere, which `.tint` cannot change, so the list itself selects nothing.
struct Sidebar: View {
  @Binding var place: Place
  /// The lesson on screen, whether the place or a page opened over it.
  let openLesson: LessonRef?
  let mentors: [Mentor]
  let kinds: [ItemKind]
  let rename: (Mentor) -> Void
  let delete: (Mentor) -> Void
  @State private var expanded: Set<EntityID> = []

  var body: some View {
    List {
      row(.start, Text(.loci("sidebar.start"))) { SidebarSymbol(name: Symbols.start) }
      if !mentors.isEmpty {
        Section {
          ForEach(mentors, id: \.id) { mentor in
            SidebarCourse(
              mentor: mentor, open: openLesson?.mentor == mentor.id ? openLesson?.lesson : nil,
              expanded: expandedBinding(mentor.id), go: { place = $0 })
          }
        } header: {
          SidebarLabel(text: Text(.loci("sidebar.courses")))
        }
      }
      Section {
        row(.library(nil), Text(.loci("sidebar.allItems"))) { SidebarSymbol(name: Symbols.library) }
        ForEach(kinds, id: \.self) { kind in
          row(.library(kind), Text(Messages.name(of: kind))) { SidebarSymbol(name: Symbols.kind(kind)) }
        }
        row(.browser, Text(.loci("sidebar.browser"))) { SidebarSymbol(name: Symbols.browser) }
      } header: {
        SidebarLabel(text: Text(.loci("sidebar.library")))
      }
      if !mentors.isEmpty {
        Section {
          ForEach(mentors, id: \.id) { mentor in
            row(.mentor(mentor.id), Text(verbatim: mentor.name)) {
              Avatar(mentor: mentor, size: Size.avatarSmall)
            }
            .contextMenu {
              Group {
                Button {
                  rename(mentor)
                } label: {
                  Text(.loci("mentor.rename"))
                }
                Button(role: .destructive) {
                  delete(mentor)
                } label: {
                  Text(.loci("mentor.delete"))
                }
              }
              .changesData()
            }
          }
        } header: {
          SidebarLabel(text: Text(.loci("sidebar.mentors")))
        }
      }
      Section {
        row(.settings(.general), Text(.loci("settings.general"))) { SidebarSymbol(name: Symbols.settings) }
        row(.settings(.agents), Text(.loci("settings.agents"))) { SidebarSymbol(name: Symbols.agents) }
        row(.settings(.media), Text(.loci("settings.media"))) { SidebarSymbol(name: Symbols.media) }
        row(.settings(.remote), Text(.loci("settings.remote"))) { SidebarSymbol(name: Symbols.remote) }
      } header: {
        SidebarLabel(text: Text(.loci("sidebar.settings")))
      }
    }
    .listStyle(.sidebar)
    .onChange(of: openLesson?.mentor, initial: true) { _, mentor in
      if let mentor { expanded.insert(mentor) }
    }
  }

  private func row(_ target: Place, _ title: Text, @ViewBuilder icon: () -> some View) -> some View {
    SidebarRow(selected: place == target, title: title, icon: icon()) { place = target }
  }

  private func expandedBinding(_ mentor: EntityID) -> Binding<Bool> {
    Binding(
      get: { expanded.contains(mentor) },
      set: { open in
        if open { expanded.insert(mentor) } else { expanded.remove(mentor) }
      })
  }
}

/// One row of the sidebar: a symbol or avatar, a title, and what trails it.
struct SidebarRow<Icon: View, Trailing: View>: View {
  let selected: Bool
  let title: Text
  let icon: Icon
  var trailing: Trailing
  let choose: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: choose) {
      HStack(spacing: Spacing.xs) {
        icon.frame(width: Size.avatarSmall)
        title.lineLimit(1).fontWeight(selected ? .semibold : .regular)
        Spacer(minLength: 0)
        trailing
      }
      .font(Typography.body)
      .foregroundStyle(Palette.ink)
      .padding(.horizontal, Spacing.xs)
      .frame(height: Size.rowHeight)
      .background(
        RoundedRectangle(cornerRadius: Radius.row).fill(
          selected ? Palette.tint : hovering ? Palette.fill : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .listRowInsets(EdgeInsets())
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

extension SidebarRow where Trailing == EmptyView {
  init(selected: Bool, title: Text, icon: Icon, choose: @escaping () -> Void) {
    self.init(selected: selected, title: title, icon: icon, trailing: EmptyView(), choose: choose)
  }
}

/// Above a group of rows.
struct SidebarLabel: View {
  let text: Text

  var body: some View {
    text.font(Typography.sectionLabel).foregroundStyle(Palette.inkFaint)
  }
}

/// A sidebar symbol in amber, as the design draws them.
struct SidebarSymbol: View {
  let name: String

  var body: some View {
    Image(systemName: name).foregroundStyle(Palette.accent)
  }
}
